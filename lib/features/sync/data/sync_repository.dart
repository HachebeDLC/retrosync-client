import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mutex/mutex.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/api_client_provider.dart';
import '../services/system_path_service.dart';

final syncRepositoryProvider = Provider<SyncRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  final pathService = ref.watch(systemPathServiceProvider);
  return SyncRepository(apiClient, pathService);
});

class SyncRepository {
  final ApiClient _apiClient;
  final SystemPathService _pathService;
  static const _platform = MethodChannel('com.vaultsync.app/launcher');
  final _syncLock = Mutex();

  SyncRepository(this._apiClient, this._pathService);

  Future<String?> _getMasterKey() async { return await _apiClient.getEncryptionKey(); }

  Future<String> _getDeviceName() async {
    final deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) { final androidInfo = await deviceInfo.androidInfo; return androidInfo.model; }
    return 'Web/PC';
  }

  // SYNC JOURNAL: Persistent tracking for SAF folders that don't support timestamp updates
  Future<void> _recordSyncSuccess(String systemId, String relPath, String remoteHash) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('journal_${systemId}_$relPath', remoteHash);
  }

  Future<bool> _isJournaledSynced(String systemId, String relPath, String remoteHash) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('journal_${systemId}_$relPath') == remoteHash;
  }

  Map<String, Map<String, dynamic>> _processLocalFiles(String systemId, List<dynamic> localList) {
    final localFiles = <String, Map<String, dynamic>>{};
    if (systemId.toLowerCase() == 'switch' || systemId.toLowerCase() == 'eden') {
      for (var f in localList) {
        final relPath = f['relPath'] as String;
        if (relPath.startsWith('nand/user/save/0000000000000000/')) {
          final parts = relPath.split('/');
          if (parts.length > 5) {
            final flattenedPath = parts.sublist(5).join('/');
            if (f['isDirectory'] == true) { localFiles[flattenedPath] = f; continue; }
            final existing = localFiles[flattenedPath];
            if (existing == null || existing['isDirectory'] == true || (f['lastModified'] as num) > (existing['lastModified'] as num)) { localFiles[flattenedPath] = f; }
          }
        } else { localFiles[relPath] = f; }
      }
    } else { for (var f in localList) { localFiles[f['relPath']] = f; } }
    return localFiles;
  }

  Future<List<Map<String, dynamic>>> diffSystem(String systemId, String localPath, {List<String>? ignoredFolders}) async {
    final effectivePath = await _pathService.getEffectivePath(systemId);
    final response = await _apiClient.get('/api/v1/files');
    final List<dynamic> fileList = response['files'] ?? [];
    final bool isRetroArch = localPath.toLowerCase().contains('retroarch');
    final String cloudPrefix = (systemId.toLowerCase() == 'eden') ? 'switch' : (isRetroArch ? 'RetroArch' : systemId);
    final remoteFiles = { for (var f in fileList) if ((f['path'] as String).startsWith('$cloudPrefix/')) f['path']: f };
    
    final String jsonResult = await _platform.invokeMethod('scanRecursive', { 'path': effectivePath, 'systemId': systemId, 'ignoredFolders': ignoredFolders ?? [] });
    final List<dynamic> localList = json.decode(jsonResult);
    final localFiles = _processLocalFiles(systemId, localList);

    final Set<String> initialRelPaths = { ...localFiles.keys, ...remoteFiles.keys.map((p) => p.substring(cloudPrefix.length + 1)) };
    final Set<String> allRelPaths = {};
    for (final path in initialRelPaths) {
      if (path.isEmpty) continue;
      allRelPaths.add(path);
      final parts = path.split('/');
      for (int i = 1; i < parts.length; i++) { allRelPaths.add(parts.sublist(0, i).join('/')); }
    }

    final List<Map<String, dynamic>> results = [];
    for (final relPath in allRelPaths) {
      String remotePath = '$cloudPrefix/$relPath';
      final localInfo = localFiles[relPath];
      final remoteInfo = remoteFiles[remotePath];
      bool isDirectory = (localInfo != null && localInfo['isDirectory'] == true) || (remoteInfo == null && !remoteFiles.containsKey(remotePath));
      String status = 'Synced'; String type = isDirectory ? 'Folder' : 'Save';
      if (!isDirectory) {
        final lowerPath = relPath.toLowerCase();
        if (lowerPath.contains('.state') || lowerPath.endsWith('.png')) type = 'State';
        if (localInfo == null) status = 'Remote Only';
        else if (remoteInfo == null) status = 'Local Only';
        else {
          final String remoteHash = remoteInfo['hash'];
          if (await _isJournaledSynced(systemId, relPath, remoteHash)) { status = 'Synced'; }
          else {
            final int localTs = (localInfo['lastModified'] as num).toInt() ~/ 1000;
            final int remoteTs = (remoteInfo['updated_at'] as num).toInt() ~/ 1000;
            final int localSize = (localInfo['size'] as num).toInt();
            final int remoteSize = (remoteInfo['size'] as num).toInt();

            if (localSize != remoteSize || localTs != remoteTs) {
              final localHash = await _platform.invokeMethod<String>('calculateHash', {'path': localInfo['uri']});
              if (localHash != remoteHash) status = 'Modified';
              else { status = 'Synced'; await _recordSyncSuccess(systemId, relPath, remoteHash); }
            }
          }
        }
      } else status = 'Folder';
      results.add({ 'relPath': relPath, 'remotePath': remotePath, 'status': status, 'type': type, 'localInfo': localInfo, 'remoteInfo': remoteInfo, 'isDirectory': isDirectory, 'name': localInfo?['name'] ?? relPath.split('/').last });
    }
    results.sort((a, b) => (a['relPath'] as String).compareTo(b['relPath'] as String));
    return results;
  }

  Future<void> syncSystem(String systemId, String localPath, {List<String>? ignoredFolders, Function(String)? onProgress, Function(String)? onError, String? filenameFilter, bool fastSync = false}) async {
    await _syncLock.protect(() async {
      final effectivePath = await _pathService.getEffectivePath(systemId);
      final bool isRetroArch = localPath.toLowerCase().contains('retroarch');
      final String cloudPrefix = (systemId.toLowerCase() == 'eden') ? 'switch' : (isRetroArch ? 'RetroArch' : systemId);
      print('🔄 SYNC: Starting system $systemId at $effectivePath (Cloud: $cloudPrefix)');
      
      try {
        final response = await _apiClient.get('/api/v1/files');
        final List<dynamic> fileList = response['files'] ?? [];
        final remoteFiles = { for (var f in fileList) if ((f['path'] as String).startsWith('$cloudPrefix/')) f['path']: f };
        
        final String jsonResult = await _platform.invokeMethod('scanRecursive', { 'path': effectivePath, 'systemId': systemId, 'ignoredFolders': ignoredFolders ?? [] });
        final List<dynamic> localList = json.decode(jsonResult);
        final localFiles = _processLocalFiles(systemId, localList);

        List<Map<String, dynamic>> toUpload = [];
        List<Map<String, dynamic>> toDownload = [];

        for (final localRelPath in localFiles.keys) {
          final localInfo = localFiles[localRelPath]!;
          if (localInfo['isDirectory'] == true) continue;
          final remotePath = '$cloudPrefix/$localRelPath';
          if (filenameFilter != null && !remotePath.contains(filenameFilter)) continue;
          
          if (!remoteFiles.containsKey(remotePath)) { toUpload.add({'local': localInfo['uri'], 'remote': remotePath, 'rel': localRelPath}); }
          else {
            final remoteInfo = remoteFiles[remotePath]!;
            final String remoteHash = remoteInfo['hash'];
            if (await _isJournaledSynced(systemId, localRelPath, remoteHash)) continue;

            final int localTs = (localInfo['lastModified'] as num).toInt() ~/ 1000;
            final int remoteTs = (remoteInfo['updated_at'] as num).toInt() ~/ 1000;
            final int localSize = (localInfo['size'] as num).toInt();
            final int remoteSize = (remoteInfo['size'] as num).toInt();

            if (localTs == remoteTs && localSize == remoteSize) {
               await _recordSyncSuccess(systemId, localRelPath, remoteHash);
               continue;
            }
            
            final localHash = await _platform.invokeMethod<String>('calculateHash', {'path': localInfo['uri']});
            if (localHash != remoteHash) {
               if (localTs > remoteTs) toUpload.add({'local': localInfo['uri'], 'remote': remotePath, 'rel': localRelPath, 'hash': localHash});
               else toDownload.add({'remote': remotePath, 'rel': localRelPath, 'serverInfo': remoteInfo, 'localInfo': localInfo});
            } else { await _recordSyncSuccess(systemId, localRelPath, remoteHash); }
          }
        }
        
        for (final remotePath in remoteFiles.keys) {
          final relPath = remotePath.substring(cloudPrefix.length + 1);
          if (filenameFilter != null && !remotePath.contains(filenameFilter)) continue;
          if (!localFiles.containsKey(relPath)) { toDownload.add({'remote': remotePath, 'rel': relPath, 'serverInfo': remoteFiles[remotePath]}); }
        }

        int count = 0; final total = toUpload.length + toDownload.length;
        for (final item in toUpload) {
          count++; onProgress?.call('Uploading ${item['rel']} ($count/$total)');
          try { await uploadFile(item['local'], item['remote'], systemId: systemId, relPath: item['rel'], plainHash: item['hash']); } catch (e) { print('❌ Upload failed: $item[rel]: $e'); }
        }
        for (final item in toDownload) {
          count++; final isPatch = (item['localInfo'] != null);
          onProgress?.call('${isPatch ? "Patching" : "Downloading"} ${item['rel']} ($count/$total)');
          try { await downloadFile(item['remote'], effectivePath, item['rel'], systemId: systemId, updatedAt: item['serverInfo']['updated_at'], serverBlocks: item['serverInfo']['blocks'], localUri: item['localInfo']?['uri']); }
          catch (e) { print('❌ Download failed: $item[rel]: $e'); }
        }
      } catch (e) { print('❌ SYNC ERROR: $e'); } 
    });
  }

  Future<void> uploadFile(dynamic localPathOrFile, String remotePath, {required String systemId, required String relPath, String? plainHash, bool force = false}) async {
    final path = localPathOrFile is File ? localPathOrFile.path : localPathOrFile.toString();
    final Map? info = await _platform.invokeMapMethod('getFileInfo', {'uri': path});
    if (info == null) return;
    final int size = info['size'];
    final int updatedAt = info['lastModified'] ?? 0;
    final String hash = plainHash ?? (await _platform.invokeMethod<String>('calculateHash', {'path': path}) ?? 'unknown');
    final masterKey = await _getMasterKey();
    final baseUrl = await _apiClient.getBaseUrl();
    final token = await _apiClient.getToken();

    List<int>? dirtyIndices;
    if (size > 1024 * 1024) {
      final String blockHashesJson = await _platform.invokeMethod('calculateBlockHashes', {'path': path});
      try {
        final checkResult = await _apiClient.post('/api/v1/blocks/check', body: {'path': remotePath, 'blocks': json.decode(blockHashesJson)});
        final List missing = checkResult['missing'] ?? [];
        if (missing.isEmpty && !force) { await _recordSyncSuccess(systemId, relPath, hash); return; }
        dirtyIndices = List<int>.from(missing);
      } catch (e) { print('⚠️ Delta check failed: $e'); }
    }

    await _platform.invokeMethod('uploadFileNative', { 'url': '$baseUrl/api/v1/upload', 'token': token, 'masterKey': masterKey, 'remotePath': remotePath, 'uri': path, 'hash': hash, 'deviceName': await _getDeviceName(), 'updatedAt': updatedAt, 'dirtyIndices': dirtyIndices });
    await _recordSyncSuccess(systemId, relPath, hash);
  }

  Future<void> downloadFile(String remotePath, String localBasePath, String relPath, {required String systemId, int? updatedAt, dynamic serverBlocks, String? localUri}) async {
    final baseUrl = await _apiClient.getBaseUrl();
    final token = await _apiClient.getToken();
    final masterKey = await _getMasterKey();
    List<int>? patchIndices;
    if (localUri != null && serverBlocks != null) {
       final String localBlocksJson = await _platform.invokeMethod('calculateBlockHashes', {'path': localUri});
       final List localHashes = json.decode(localBlocksJson);
       final List remoteHashes = serverBlocks is String ? json.decode(serverBlocks) : serverBlocks;
       final dirty = <int>[];
       for (int i = 0; i < remoteHashes.length; i++) { if (i >= localHashes.length || localHashes[i] != remoteHashes[i]) { dirty.add(i); } }
       if (dirty.isNotEmpty && dirty.length < remoteHashes.length) { patchIndices = dirty; }
    }
    await _platform.invokeMethod('downloadFileNative', { 'url': '$baseUrl/api/v1/download', 'token': token, 'masterKey': masterKey, 'remoteFilename': remotePath, 'uri': localBasePath, 'localFilename': relPath, 'updatedAt': updatedAt, 'patchIndices': patchIndices });
    
    final effectiveLocalUri = '$localBasePath/$relPath'.replaceAll('//', '/');
    final String finalHash = await _platform.invokeMethod<String>('calculateHash', {'path': localUri ?? effectiveLocalUri}) ?? '';
    await _recordSyncSuccess(systemId, relPath, finalHash);
  }

  Future<void> deleteRemoteFile(String path) async { await _apiClient.delete('/api/v1/files', body: {'filename': path}); }
  Future<List<Map<String, dynamic>>> getFileVersions(String remotePath) async { final response = await _apiClient.get('/api/v1/versions?path=$remotePath'); return List<Map<String, dynamic>>.from(response['versions'] ?? []); }
  Future<void> restoreVersion(String remotePath, int version, String localBasePath, String relPath) async {
    final baseUrl = await _apiClient.getBaseUrl();
    final token = await _apiClient.getToken();
    final masterKey = await _getMasterKey();
    await _platform.invokeMethod('downloadFileNative', { 'url': '$baseUrl/api/v1/versions/restore', 'token': token, 'masterKey': masterKey, 'remoteFilename': remotePath, 'version': version, 'uri': localBasePath, 'localFilename': relPath });
  }
  Future<void> deleteSystemCloudData(String systemId) async { await _apiClient.delete('/api/v1/systems/$systemId'); }
  Future<List<Map<String, dynamic>>> getAllRemoteConflicts() async { try { final response = await _apiClient.get('/api/v1/conflicts'); return List<Map<String, dynamic>>.from(response['conflicts'] ?? []); } catch(_) { return []; } }
  Future<Map<String, dynamic>> scanLocalFiles(String path, String systemId) async {
    final String result = await _platform.invokeMethod('scanRecursive', {'path': path, 'systemId': systemId});
    final List list = json.decode(result);
    return { for (var f in list) f['relPath']: f };
  }
}
