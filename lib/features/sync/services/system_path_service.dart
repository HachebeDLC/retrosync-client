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
  return service.getAllSystemPaths();
});

class SystemPathService {
  final EmulatorRepository _emulatorRepository;
  static const _platform = MethodChannel('com.neosync.app/launcher');

  SystemPathService(this._emulatorRepository);

  static const Map<String, String> standaloneDefaults = {
    'aethersx2': '/storage/emulated/0/Android/data/xyz.aethersx2.android/files/memcards',
    'nethersx2': '/storage/emulated/0/Android/data/xyz.aethersx2.android/files/memcards',
    'ppsspp': '/storage/emulated/0/PSP/SAVEDATA',
    'duckstation': '/storage/emulated/0/Android/data/com.github.stenzek.duckstation/files/memcards',
    'duckstation_legacy': '/storage/emulated/0/DuckStation/memcards',
    'dolphin': '/storage/emulated/0/Android/data/org.dolphinemu.dolphinemu/files',
    'citra': '/storage/emulated/0/citra-emu/sdmc',
    'yuzu': '/storage/emulated/0/Android/data/org.yuzu.yuzu_emu/files',
    'eden': '/storage/emulated/0/Android/data/dev.eden.eden_emulator/files',
    'eden_legacy': '/storage/emulated/0/Android/data/dev.legacy.eden_emulator/files',
    'eden_optimized': '/storage/emulated/0/Android/data/com.miHoYo.Yuanshen/files',
    'eden_nightly': '/storage/emulated/0/Android/data/dev.eden.eden_nightly/files',
    '3ds.azahar': '/storage/emulated/0/Android/data/io.github.lime3ds.android/files/sdmc',
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
            if (line.startsWith('savefile_directory')) saves = line.split('=').last.replaceAll('"', '').trim();
            else if (line.startsWith('savestate_directory')) states = line.split('=').last.replaceAll('"', '').trim();
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

  Future<void> setSystemPath(String systemId, String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('system_path_$systemId', path);
  }

  Future<String?> getSystemEmulator(String systemId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('system_emulator_$systemId');
  }

  Future<void> setSystemEmulator(String systemId, String emulatorId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('system_emulator_$systemId', emulatorId);
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
    final keys = prefs.getKeys().where((k) => k.startsWith('system_path_'));
    final paths = <String, String>{};
    for (final key in keys) {
      final systemId = key.replaceFirst('system_path_', '');
      final path = prefs.getString(key);
      if (path != null) paths[systemId] = path;
    }
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

    // Trigger the picker for the restricted path
    print('🔐 PERMISSION: Requesting SAF access for $path');
    final pickedUri = await openDirectoryPicker();
    
    if (pickedUri != null) {
      await prefs.setString('saf_uri_$path', pickedUri);
      return true;
    }
    
    return false;
  }

  Future<String> getEffectivePath(String systemId) async {
    final path = await getSystemPath(systemId) ?? suggestSavePathById(systemId);
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('saf_uri_$path') ?? path;
  }

  Future<String?> openDirectoryPicker({String? initialUri}) async {
    try { 
      return await _platform.invokeMethod('openSafDirectoryPicker', {
        if (initialUri != null) 'initialUri': initialUri,
      }); 
    } catch (_) { return null; }
  }

  Future<List<String>> scanLibrary(String rootPath) async {
    print('🔍 SCAN: Initiating Library-First scan on $rootPath');
    final systems = await _emulatorRepository.loadSystems();
    final raPaths = await getRetroArchPaths();
    final foundSystemIds = <String>[];
    
    List<Map<String, dynamic>> rootFolders = [];
    if (rootPath.startsWith('content://')) {
       try {
         final List<dynamic> result = await _platform.invokeMethod('listSafDirectory', {'uri': rootPath});
         rootFolders = result.map((e) => Map<String, dynamic>.from(e)).where((f) => f['isDirectory'] == true).toList();
       } catch (e) { print('❌ SCAN: SAF failed: $e'); }
    } else {
       final dir = Directory(rootPath);
       if (await dir.exists()) {
          rootFolders = dir.listSync().whereType<Directory>().map((d) => {'name': d.path.split('/').last, 'uri': d.path}).toList();
       }
    }

    print('📂 SCAN: Found ${rootFolders.length} folders in library. Matching against systems...');

    for (final folder in rootFolders) {
      final folderName = folder['name'].toString().toLowerCase();
      final folderUri = folder['uri'].toString();
      
      for (final systemConfig in systems) {
        final system = systemConfig.system;
        if (foundSystemIds.contains(system.id)) continue;

        bool isMatch = folderName == system.id.toLowerCase() || 
                       folderName == system.name.toLowerCase() || 
                       system.folders.any((f) => f.toLowerCase() == folderName);

        if (isMatch) {
          if (await _hasValidRoms(folderUri, system.extensions)) {
            print('✅ SCAN: System ${system.id} confirmed in "$folderName"');
            
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
              bestSavePath = raPaths['saves'];
              bestEmulatorId = 'retroarch';
              print('🕹️ SCAN: No standalone found for ${system.id}, defaulting to RetroArch');
            }

            if (bestSavePath != null) {
              foundSystemIds.add(system.id);
              await setSystemPath(system.id, bestSavePath);
              if (bestEmulatorId != null) await setSystemEmulator(system.id, bestEmulatorId);
            }
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
