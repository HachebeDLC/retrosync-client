import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../emulation/data/emulator_repository.dart';
import '../../emulation/domain/emulator_config.dart';

final systemPathServiceProvider = Provider<SystemPathService>((ref) {
  final emulatorRepo = ref.watch(emulatorRepositoryProvider);
  return SystemPathService(emulatorRepo);
});

final systemPathsProvider = FutureProvider<Map<String, String>>((ref) async {
  final service = ref.watch(systemPathServiceProvider);
  // Watch for changes in storage version to force reload
  await service.getStorageVersion(); 
  return service.getAllSystemPaths();
});

class SystemPathService {
  final EmulatorRepository _emulatorRepository;
  static const _platform = MethodChannel('com.vaultsync.app/launcher');

  SystemPathService(this._emulatorRepository);

  EmulatorRepository getEmulatorRepository() => _emulatorRepository;

  static const Map<String, String> standaloneDefaults = {
    'aethersx2': '/storage/emulated/0/Android/data/xyz.aethersx2.android/files/memcards',
    'nethersx2': '/storage/emulated/0/Android/data/xyz.aethersx2.android/files/memcards',
    'ppsspp': '/storage/emulated/0/PSP/SAVEDATA',
    'duckstation': '/storage/emulated/0/Android/data/com.github.stenzek.duckstation/files/memcards',
    'duckstation_legacy': '/storage/emulated/0/DuckStation/memcards',
    'dolphin': '/storage/emulated/0/Android/data/org.dolphinemu.dolphinemu/files',
    'citra': '/storage/emulated/0/Citra',
    'yuzu': '/storage/emulated/0/Android/data/org.yuzu.yuzu_emu/files',
    'eden': '/storage/emulated/0/Android/data/dev.eden.eden_emulator/files',
    'eden_legacy': '/storage/emulated/0/Android/data/dev.legacy.eden_emulator/files',
    'eden_optimized': '/storage/emulated/0/Android/data/com.miHoYo.Yuanshen/files',
    'eden_nightly': '/storage/emulated/0/Android/data/dev.eden.eden_nightly/files',
    '3ds.azahar': '/storage/emulated/0/Azahar',
    'redream': '/storage/emulated/0/Android/data/io.recompiled.redream/files/saves',
    'flycast': '/storage/emulated/0/flycast/data',
    'melonds': '/storage/emulated/0/Android/data/me.magnum.melonds/files/saves',
  };

  Future<Map<String, String>> getRetroArchPaths() async {
    const configPaths = [
      '/storage/emulated/0/Android/data/com.retroarch/files/retroarch.cfg',
      '/storage/emulated/0/Android/data/com.retroarch.aarch64/files/retroarch.cfg',
      '/storage/emulated/0/Android/data/com.retroarch.ra32/files/retroarch.cfg',
      '/storage/emulated/0/RetroArch/retroarch.cfg',
    ];
    for (final path in configPaths) {
      final file = File(path);
      if (await file.exists()) {
        try {
          final lines = await file.readAsLines();
          String? saves;
          String? states;
          for (final line in lines) {
            if (line.startsWith('savefile_directory')) {
              saves = line.split('=').last.replaceAll('"', '').trim();
            } else if (line.startsWith('savestate_directory')) states = line.split('=').last.replaceAll('"', '').trim();
          }
          if (saves != null || states != null) {
            return {'saves': saves ?? '/storage/emulated/0/RetroArch/saves', 'states': states ?? '/storage/emulated/0/RetroArch/states'};
          }
        } catch (_) {}
      }
    }
    return {'saves': '/storage/emulated/0/RetroArch/saves', 'states': '/storage/emulated/0/RetroArch/states'};
  }

  Future<String?> getLibraryPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('rom_library_path');
  }

  Future<void> setLibraryPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('rom_library_path', path);
  }

  Future<String?> getSystemPath(String systemId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('system_path_$systemId');
  }

  Future<void> clearAllSystems() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith('system_path_') || k.startsWith('system_emulator_'));
    for (final key in keys) {
      await prefs.remove(key);
    }
    await _incrementStorageVersion();
    print('🧹 STORAGE: Cleared all system configurations');
  }

  Future<void> _incrementStorageVersion() async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt('storage_version') ?? 0;
    await prefs.setInt('storage_version', current + 1);
  }

  Future<int> getStorageVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('storage_version') ?? 0;
  }

  Future<void> setSystemPath(String systemId, String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('system_path_$systemId', path);
    await _incrementStorageVersion();
    print('💾 STORAGE: Saved path for $systemId -> $path');
  }

  Future<String?> getSystemEmulator(String systemId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('system_emulator_$systemId');
  }

  Future<void> setSystemEmulator(String systemId, String emulatorId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('system_emulator_$systemId', emulatorId);
    await _incrementStorageVersion();
    print('💾 STORAGE: Saved emulator for $systemId -> $emulatorId');
  }

  String suggestSavePath(EmulatorInfo emulator, String systemId) {
    for (final entry in standaloneDefaults.entries) {
      if (emulator.uniqueId.contains(entry.key)) {
        String path = entry.value;
        if (entry.key == 'dolphin') {
          if (systemId == 'gc') path = '$path/GC';
          if (systemId == 'wii') path = '$path/Wii';
        }
        return path;
      }
    }
    return '/storage/emulated/0/RetroArch/saves';
  }

  String suggestSavePathById(String systemId) {
    for (final entry in standaloneDefaults.entries) {
      if (systemId.toLowerCase().contains(entry.key)) {
        String path = entry.value;
        if (entry.key == 'dolphin') {
          if (systemId == 'gc') path = '$path/GC';
          if (systemId == 'wii') path = '$path/Wii';
        }
        return path;
      }
    }
    return '/storage/emulated/0/RetroArch/saves';
  }

  Future<String?> getSwitchSavePathForGame(String systemId, String gameId) async {
    final basePath = await getSystemPath(systemId);
    if (basePath == null) return null;
    return '$basePath/nand/user/save/0000000000000000/$gameId';
  }

  Future<Map<String, String>> getAllSystemPaths() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload(); // Force sync with disk on Android
    final keys = prefs.getKeys().where((k) => k.startsWith('system_path_'));
    final paths = <String, String>{};
    for (final key in keys) {
      final systemId = key.replaceFirst('system_path_', '');
      final path = prefs.getString(key);
      if (path != null) paths[systemId] = path;
    }
    print('📂 STORAGE: Reloaded and found ${paths.length} configured systems');
    return paths;
  }

  Future<bool> ensureSafPermission(String path) async {
    // If it's not a restricted path, no SAF needed for targetSDK 29
    if (!path.contains('/Android/data/')) return true;
    
    // Check if we already have a content:// URI for this path or if we have permission
    final prefs = await SharedPreferences.getInstance();
    final persistedUri = prefs.getString('saf_uri_$path');
    
    if (persistedUri != null) {
      final hasPermission = await _platform.invokeMethod<bool>('checkSafPermission', {'uri': persistedUri});
      if (hasPermission == true) return true;
    }

    // Generate initial URI hint for the picker
    String? initialUri;
    if (path.startsWith('/storage/emulated/0/')) {
      String relPath = path.substring(20).replaceAll('/', '%2F');
      
      // SAF navigation to subfolders in Android/data is often restricted.
      // We target the package root in Android/data, which is the deepest reliable hint.
      if (path.contains('/Android/data/')) {
        final parts = path.split('/Android/data/');
        if (parts.length > 1) {
          final packageName = parts[1].split('/').first;
          relPath = 'Android%2Fdata%2F$packageName';
        } else {
          relPath = 'Android';
        }
      }
      
      // Use the 'tree' format for better reliability
      initialUri = 'content://com.android.externalstorage.documents/tree/primary%3A$relPath';
    }

    // Trigger the picker for the restricted path
    print('🔐 PERMISSION: Requesting SAF access for $path (Hint: $initialUri)');
    final pickedUri = await openDirectoryPicker(initialUri: initialUri);
    
    if (pickedUri != null) {
      await prefs.setString('saf_uri_$path', pickedUri);
      return true;
    }
    
    return false;
  }

  Future<String> getEffectivePath(String systemId) async {
    final path = await getSystemPath(systemId);
    if (path == null) return suggestSavePathById(systemId);
    
    if (path.startsWith('content://')) return path;

    final prefs = await SharedPreferences.getInstance();
    final persistedUri = prefs.getString('saf_uri_$path');
    
    if (persistedUri != null) {
      final hasPermission = await _platform.invokeMethod<bool>('checkSafPermission', {'uri': persistedUri});
      if (hasPermission == true) {
        // We have permission for a parent folder (e.g. the package root).
        // Build a specific sub-document URI for the intended path.
        if (path.startsWith('/storage/emulated/0/')) {
           final relPath = path.substring(20).replaceAll('/', '%2F');
           // Combine the tree root with the specific document path
           return '$persistedUri/document/primary%3A$relPath';
        }
        return persistedUri;
      }
    }
    
    return path;
  }

  Future<String?> openDirectoryPicker({String? initialUri}) async {
    print('📂 PICKER: Requesting with initialUri hint: $initialUri');
    try { 
      // Ensure the hint URI is properly encoded for the native side
      final result = await _platform.invokeMethod('openSafDirectoryPicker', {
        'initialUri': initialUri,
      }); 
      print('📂 PICKER: Result: $result');
      return result;
    } catch (e) { 
      print('❌ PICKER: Error: $e');
      return null; 
    }
  }

  Future<List<String>> scanLibrary(String rootPath) async {
    print('🔍 SCAN: Initiating Library-First scan on $rootPath');
    final systems = await _emulatorRepository.loadSystems();
    final raPaths = await getRetroArchPaths();
    final foundSystemIds = <String>[];
    
    List<Map<String, dynamic>> rootFolders = [];
    if (rootPath.startsWith('content://')) {
       try {
         final String resultStr = await _platform.invokeMethod('listSafDirectory', {'uri': rootPath});
         final List<dynamic> result = json.decode(resultStr);
         rootFolders = result.map((e) => Map<String, dynamic>.from(e)).where((f) => f['isDirectory'] == true).toList();
       } catch (e) { print('❌ SCAN: SAF failed: $e'); }
    } else {
       final dir = Directory(rootPath);
       if (await dir.exists()) {
          rootFolders = dir.listSync().whereType<Directory>().map((d) => {'name': d.path.split('/').last, 'uri': d.path}).toList();
       }
    }

    final Set<String> matchedFolderUris = {};
    print('📂 SCAN: Found ${rootFolders.length} folders in library. Matching against systems...');

    for (final folder in rootFolders) {
      final folderName = folder['name'].toString().toLowerCase();
      final folderUri = folder['uri'].toString();
      
      if (matchedFolderUris.contains(folderUri)) continue;

      // SKIP: If the folder name is too generic, it must match EXACTLY to a system folders list
      final genericFolders = {'roms', 'saves', 'states', 'data', 'games', 'game', 'media', 'files', 'configs', 'content'};
      bool isGeneric = genericFolders.contains(folderName);

      for (final systemConfig in systems) {
        final system = systemConfig.system;
        if (foundSystemIds.contains(system.id)) continue;

        // MATCH CRITERIA:
        // 1. If it's a specific system folder (e.g. "ps2", "snes") -> MATCH
        // 2. If it's a generic folder -> ONLY MATCH if system ID matches folder name exactly
        bool isPerfectMatch = folderName == system.id.toLowerCase() || 
                              folderName == system.name.toLowerCase().replaceAll(' ', '');
        
        bool isAliasMatch = !isGeneric && system.folders.any((f) => f.toLowerCase() == folderName);

        if (isPerfectMatch || isAliasMatch) {
          // HARDENING: Only validate against "heavy" extensions (roms/saves), not metadata (png/txt)
          final filteredExts = system.extensions.where((e) => !['png', 'txt', 'jpg', 'xml', 'json', 'pdf', 'htm', 'html', 'nomedia'].contains(e.toLowerCase())).toList();
          
          if (await _hasValidRoms(folderUri, filteredExts.isNotEmpty ? filteredExts : system.extensions)) {
            print('✅ SCAN: System ${system.id} confirmed in "$folderName"');
            matchedFolderUris.add(folderUri);
            foundSystemIds.add(system.id);
            
            String? bestSavePath;
            String? bestEmulatorId;

            for (final entry in standaloneDefaults.entries) {
              if (systemConfig.emulators.any((e) => e.uniqueId.contains(entry.key))) {
                bool exists = await _platform.invokeMethod<bool>('checkPathExists', {'path': entry.value}) ?? false;
                if (exists) {
                   bestSavePath = entry.value;
                   bestEmulatorId = entry.key;
                   if (entry.key == 'dolphin') {
                      if (system.id == 'gc') bestSavePath = '${entry.value}/GC';
                      if (system.id == 'wii') bestSavePath = '${entry.value}/Wii';
                   }
                   break;
                }
              }
            }

            if (bestSavePath == null) {
              final ra = await getRetroArchPaths();
              bestSavePath = ra['saves'];
              bestEmulatorId = 'retroarch';
            }

            if (bestSavePath != null) {
              await setSystemPath(system.id, bestSavePath);
              if (bestEmulatorId != null) await setSystemEmulator(system.id, bestEmulatorId);
              print('💾 SCAN: Persisted ${system.id} to $bestSavePath');
              foundSystemIds.add(system.id);
            }
            break; // Stop looking for systems for this folder once a match is found
          }
        }
      }
    }

    print('🏁 SCAN: Library-First scan complete. Found ${foundSystemIds.length} systems.');
    return foundSystemIds;
  }

  Future<bool> _hasValidRoms(String path, List<String> extensions) async {
    if (path.startsWith('content://')) {
       return await _platform.invokeMethod<bool>('hasFilesWithExtensions', {
         'uri': path,
         'extensions': extensions
       }) ?? false;
    } else {
      final lowerExts = extensions.map((e) => e.toLowerCase()).toSet();
      lowerExts.removeAll(['txt', 'bak', 'nomedia', 'tmp']);
      final dir = Directory(path);
      if (await dir.exists()) {
        try {
          await for (final e in dir.list(recursive: true).take(100)) { 
            if (e is File) {
              final ext = e.path.split('.').last.toLowerCase();
              if (lowerExts.contains(ext)) return true;
            }
          }
        } catch (_) {}
      }
    }
    return false;
  }
}
