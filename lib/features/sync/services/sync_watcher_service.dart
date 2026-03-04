import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:watcher/watcher.dart';
import 'system_path_service.dart';
import '../data/sync_repository.dart';
import '../domain/sync_provider.dart';

final syncWatcherServiceProvider = Provider<SyncWatcherService>((ref) {
  return SyncWatcherService(ref);
});

class SyncWatcherService {
  final Ref _ref;
  final Map<String, StreamSubscription> _subscriptions = {};

  SyncWatcherService(this._ref);

  Future<void> startWatching() async {
    final pathsAsync = await _ref.read(systemPathsProvider.future);
    
    // Cancel existing
    for (var sub in _subscriptions.values) {
      sub.cancel();
    }
    _subscriptions.clear();

    for (var entry in pathsAsync.entries) {
      final systemId = entry.key;
      final path = entry.value;

      if (path.startsWith('content://')) continue; // Can't watch SAF directly with watcher package easily

      final dir = Directory(path);
      if (await dir.exists()) {
        print('Watcher: Starting for $systemId at $path');
        final watcher = DirectoryWatcher(path);
        _subscriptions[systemId] = watcher.events.listen((event) {
          if (event.type == ChangeType.MODIFY || event.type == ChangeType.ADD) {
             _handleFileChange(systemId, path, event.path);
          }
        });
      }
    }
  }

  void stopWatching() {
    for (var sub in _subscriptions.values) {
      sub.cancel();
    }
    _subscriptions.clear();
  }

  // Debouncing to avoid rapid syncs during a single save operation
  final Map<String, Timer> _debounceTimers = {};

  void _handleFileChange(String systemId, String basePath, String filePath) {
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
            systemId, 
            basePath,
            filenameFilter: filePath.split(Platform.pathSeparator).last,
          );
          _ref.read(syncProvider.notifier).updateStatus('Live Sync: ${filePath.split(Platform.pathSeparator).last} updated');
       } catch (e) {
          print('Watcher Sync Error: $e');
       }
    });
  }
}
