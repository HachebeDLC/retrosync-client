import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:http/http.dart' as http;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/api_client_provider.dart';

final syncRepositoryProvider = Provider<SyncRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return SyncRepository(apiClient);
});

class SyncRepository {
  final ApiClient _apiClient;
  static const _platform = MethodChannel('com.neosync.app/launcher');
  bool _isSyncingGlobal = false;

  SyncRepository(this._apiClient);

  Future<String?> _getMasterKey() async {
    return await _apiClient.getEncryptionKey();
  }

  Future<String> _getDeviceName() async {
    final deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      return androidInfo.model;
    }
    return 'Web/PC';
  }

  Future<void> syncSystem(String systemId, String localPath, {Function(String)? onProgress, String? filenameFilter}) async {
    if (_isSyncingGlobal) return;
    _isSyncingGlobal = true;
    print('🔄 SYNC: Starting system $systemId at $localPath');
    
    try {
      final response = await _apiClient.get('/api/v1/files');
      final List<dynamic> fileList = response['files'] ?? [];
      final remoteFiles = { for (var f in fileList) if ((f['path'] as String).startsWith('$systemId/')) f['path']: f };
      
      final String jsonResult = await _platform.invokeMethod('scanRecursive', {'path': localPath, 'systemId': systemId});
      final List<dynamic> localList = json.decode(jsonResult);
      final localFiles = { for (var f in localList) f['relPath']: f };

      List<Map<String, dynamic>> toUpload = [];
      List<Map<String, dynamic>> toDownload = [];

      for (final localRelPath in localFiles.keys) {
        final localInfo = localFiles[localRelPath]!;
        final remotePath = '$systemId/$localRelPath';
        if (filenameFilter != null && !remotePath.contains(filenameFilter)) continue;

        if (!remoteFiles.containsKey(remotePath)) {
          final hash = await _platform.invokeMethod<String>('calculateHash', {'path': localInfo['uri']});
          toUpload.add({'local': localInfo['uri'], 'remote': remotePath, 'rel': localRelPath, 'hash': hash});
        } else {
          final remoteInfo = remoteFiles[remotePath]!;
          final localHash = await _platform.invokeMethod<String>('calculateHash', {'path': localInfo['uri']});
          
          if (localHash != remoteInfo['hash']) {
            // CONFLICT DETECTION:
            // 1. If local is NEWER than cloud: UPLOAD
            // 2. If cloud is NEWER than local: DOWNLOAD
            // 3. If they differ but timestamps are identical (rare): CLOUD WINS (SAFER)
            final int localTs = (localInfo['lastModified'] as num).toInt();
            final int remoteTs = (remoteInfo['updated_at'] as num).toInt();

            if (localTs > remoteTs) {
              toUpload.add({'local': localInfo['uri'], 'remote': remotePath, 'rel': localRelPath, 'hash': localHash});
            } else if (remoteTs > localTs) {
              toDownload.add({'remote': remotePath, 'rel': localRelPath});
            } else {
              // Exact timestamp match but hash mismatch -> Download cloud version to be safe
              toDownload.add({'remote': remotePath, 'rel': localRelPath});
            }
          }
        }
      }

      for (final remotePath in remoteFiles.keys) {
        final relPath = remotePath.substring(systemId.length + 1);
        if (filenameFilter != null && !remotePath.contains(filenameFilter)) continue;
        if (!localFiles.containsKey(relPath)) {
          toDownload.add({'remote': remotePath, 'rel': relPath});
        }
      }

      print('📊 SYNC: Calculated diffs. Uploading ${toUpload.length} files. Downloading ${toDownload.length} files.');
      int count = 0;
      final total = toUpload.length + toDownload.length;

      for (final item in toUpload) {
        count++;
        onProgress?.call('Uploading ${item['rel']} ($count/$total)');
        await uploadFile(item['local'], item['remote'], plainHash: item['hash']);
      }
      for (final item in toDownload) {
        count++;
        onProgress?.call('Downloading ${item['rel']} ($count/$total)');
        await downloadFile(item['remote'], localPath, item['rel']);
      }
    } catch (e) { print('❌ SYNC ERROR: $e'); } 
    finally { _isSyncingGlobal = false; }
  }

  Future<void> uploadFile(dynamic localPathOrFile, String remotePath, {String? plainHash, bool force = false}) async {
    final path = localPathOrFile is File ? localPathOrFile.path : localPathOrFile.toString();
    print('📦 SYNC: Processing upload for $remotePath');
    
    final Map<String, dynamic>? info = await _platform.invokeMapMethod('getFileInfo', {'uri': path});
    if (info == null) return;
    final int size = info['size'];
    final int updatedAt = info['lastModified'] ?? 0;
    final String hash = plainHash ?? (await _platform.invokeMethod<String>('calculateHash', {'path': path}) ?? 'unknown');
    final deviceName = await _getDeviceName();
    final masterKey = await _getMasterKey();

    final baseUrl = await _apiClient.getBaseUrl();
    final token = await _apiClient.getToken();

    List<int>? dirtyIndices;

    // Delta sync only for large files (>1MB)
    if (size > 1024 * 1024) {
      final String blockHashesJson = await _platform.invokeMethod('calculateBlockHashes', {'path': path});
      final List<dynamic> blockHashes = json.decode(blockHashesJson);
      
      try {
        final checkResult = await _apiClient.post('/api/v1/blocks/check', body: {'path': remotePath, 'blocks': blockHashes});
        final List<dynamic> missing = checkResult['missing'] ?? [];
        if (missing.isEmpty) {
           print('✅ SYNC: Blocks already match for $remotePath');
           return;
        }
        dirtyIndices = List<int>.from(missing);
        print('🚀 SYNC: Patching ${dirtyIndices.length} blocks for $remotePath');
      } catch (e) { print('⚠️ Delta check failed, forcing full sync: $e'); }
    }

    // MANDATORY NATIVE STREAMER: Cloudflare-safe and RAM-efficient for all files
    await _platform.invokeMethod('uploadFileNative', {
      'url': '$baseUrl/api/v1/upload',
      'token': token,
      'masterKey': masterKey,
      'remotePath': remotePath,
      'uri': path,
      'hash': hash,
      'deviceName': deviceName,
      'updatedAt': updatedAt,
      'dirtyIndices': dirtyIndices, // null = full sequential sync
    });
    
    print('✅ SYNC: Native Turbo Upload complete: $remotePath');
  }

  Future<void> downloadFile(String remotePath, String localBasePath, String relPath) async {
    print('📥 SYNC: Turbo Downloading $remotePath...');
    final baseUrl = await _apiClient.getBaseUrl();
    final token = await _apiClient.getToken();
    final masterKey = await _getMasterKey();

    await _platform.invokeMethod('downloadFileNative', {
      'url': '$baseUrl/api/v1/download',
      'token': token,
      'masterKey': masterKey,
      'remoteFilename': remotePath,
      'uri': localBasePath,
      'localFilename': relPath,
    });
    print('✅ SYNC: Native Turbo Download complete: $relPath');
  }

  Future<void> deleteRemoteFile(String path) async {
    await _apiClient.delete('/api/v1/files', body: {'filename': path});
  }

  Future<void> deleteSystemCloudData(String systemId) async { }
  Future<List<Map<String, dynamic>>> getAllRemoteConflicts() async { return []; }

  Future<Map<String, dynamic>> scanLocalFiles(String path, String systemId) async {
    final String result = await _platform.invokeMethod('scanRecursive', {'path': path, 'systemId': systemId});
    final List<dynamic> list = json.decode(result);
    return { for (var f in list) f['relPath']: f };
  }
}
