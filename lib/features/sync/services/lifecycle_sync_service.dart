import 'dart:developer' as developer;
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/sync_provider.dart';
import '../../../core/services/connectivity_provider.dart';
import 'background_sync_service.dart';
import 'sync_service.dart';
import 'system_path_service.dart';

final lifecycleSyncServiceProvider = Provider<LifecycleSyncService>((ref) {
  final service = LifecycleSyncService(ref);
  ref.onDispose(() => service.dispose());
  return service;
});

class LifecycleSyncService with WidgetsBindingObserver {
  final Ref _ref;
  static const _platform = MethodChannel('com.vaultsync.app/launcher');

  LifecycleSyncService(this._ref) {
    WidgetsBinding.instance.addObserver(this);
    _initConnectivityListener();
  }

  void _initConnectivityListener() {
    _ref.listen<bool>(isOnlineProvider, (previous, next) {
      if (previous == false && next == true) {
        developer.log(
            'LIFECYCLE: Device is back online. Triggering offline queue...',
            name: 'VaultSync',
            level: 800);
        _ref.read(syncServiceProvider).processOfflineQueue();
      }
    }, fireImmediately: true);
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAndTriggerSync();
    }
  }

  Future<void> _checkAndTriggerSync() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!(prefs.getBool('auto_sync_on_exit') ?? false)) return;

      // On Linux/desktop: resumed = app regained focus (user came back from a
      // game session). No process-level detection needed — just sync.
      if (Platform.isLinux || Platform.isWindows) {
        developer.log('LIFECYCLE: App resumed on desktop. Triggering sync.',
            name: 'VaultSync', level: 800);
        _ref.read(syncProvider.notifier).sync();
        return;
      }

      // Android: require usage stats permission to detect which emulator closed.
      bool hasPermission = false;
      if (Platform.isAndroid) {
        hasPermission =
            await _platform.invokeMethod('hasUsageStatsPermission') ?? false;
      }
      if (!hasPermission) return;

      String? closedPackage;
      if (Platform.isAndroid) {
        closedPackage =
            await _platform.invokeMethod('getRecentlyClosedEmulator', {
          'packages': BackgroundSyncService.packageToSystem.keys.toList(),
        });
      }

      if (closedPackage != null) {
        final systemId = BackgroundSyncService.packageToSystem[closedPackage];
        developer.log(
          'LIFECYCLE: Detected recently active emulator $closedPackage. Triggering ${systemId ?? 'full'} sync.',
          name: 'VaultSync',
          level: 800,
        );
        if (systemId != null) {
          final pathService = _ref.read(systemPathServiceProvider);
          final path = await pathService.getEffectivePath(systemId);
          final systems =
              await pathService.getEmulatorRepository().loadSystems();
          final config =
              systems.where((s) => s.system.id == systemId).firstOrNull;
          await _ref.read(syncProvider.notifier).syncSingleSystem(
                systemId,
                path,
                ignoredFolders: config?.system.ignoredFolders,
              );
        } else {
          await _ref.read(syncProvider.notifier).sync();
        }
      }
    } catch (e) {
      developer.log('LIFECYCLE: Sync error',
          name: 'VaultSync', level: 1000, error: e);
    }
  }
}
