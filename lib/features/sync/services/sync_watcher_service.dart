import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'system_path_service.dart';
import '../data/sync_repository.dart';
import '../domain/sync_provider.dart';

final syncWatcherServiceProvider = Provider<SyncWatcherService>((ref) {
  return SyncWatcherService(ref);
});

class SyncWatcherService {
  final Ref _ref;
  static const _platform = MethodChannel('com.vaultsync.app/launcher');
  final List<String> _watchedPaths = [];

  SyncWatcherService(this._ref) {
    _platform.setMethodCallHandler((call) async {
      if (call.method == 'onFileSystemEvent') {
        final String path = call.arguments['path'];
        _handleNativeEvent(path);
      }
    });
  }

  Future<void> startWatching() async {
    final pathsAsync = await _ref.read(systemPathsProvider.future);
    
    // Stop old ones
    for (final path in _watchedPaths) {
      await _platform.invokeMethod('stopWatchingPath', {'path': path});
    }
    _watchedPaths.clear();

    for (var entry in pathsAsync.entries) {
      final systemId = entry.key;
      final path = entry.value;

      print('Watcher: Registering native watcher for $systemId at $path');
      try {
        await _platform.invokeMethod('startWatchingPath', {'path': path});
        _watchedPaths.add(path);
        _systemIdMap[path] = systemId;
      } catch (e) {
        print('Watcher Error: Could not start native watcher for $path: $e');
      }
    }
  }

  void stopWatching() {
    for (final path in _watchedPaths) {
      _platform.invokeMethod('stopWatchingPath', {'path': path});
    }
    _watchedPaths.clear();
  }

  final Map<String, String> _systemIdMap = {};
  final Map<String, Timer> _debounceTimers = {};

  void _handleNativeEvent(String filePath) {
    // Find which system this file belongs to
    String? systemId;
    String? basePath;
    
    for (final watchedPath in _watchedPaths) {
      if (filePath.startsWith(watchedPath)) {
        systemId = _systemIdMap[watchedPath];
        basePath = watchedPath;
        break;
      }
    }

    if (systemId == null || basePath == null) return;

    // Only sync allowed extensions
    final ext = filePath.split('.').last.toLowerCase();
    const allowed = ['srm', 'sav', 'state', 'auto', 'mcd', 'ps2', 'dat'];
    if (!allowed.contains(ext)) return;

    final timerKey = '$systemId:$filePath';
    _debounceTimers[timerKey]?.cancel();
    _debounceTimers[timerKey] = Timer(const Duration(seconds: 5), () async {
       print('Watcher: Triggering sync for $filePath');
       try {
          await _ref.read(syncRepositoryProvider).syncSystem(
            systemId!, 
            basePath!,
            filenameFilter: filePath.split(Platform.pathSeparator).last,
            fastSync: true, // Auto-sync uses Fast Mode to save battery/data
          );
          _ref.read(syncProvider.notifier).updateStatus('Live Sync: ${filePath.split(Platform.pathSeparator).last} updated');
       } catch (e) {
          print('Watcher Sync Error: $e');
       }
    });
  }
}
