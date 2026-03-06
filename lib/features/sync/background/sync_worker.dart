import 'package:workmanager/workmanager.dart';
import '../../../core/services/api_client.dart';
import '../../emulation/data/emulator_repository.dart';
import '../data/sync_repository.dart';
import '../services/sync_service.dart';
import '../services/system_path_service.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    print("Native called background task: $task");
    
    // This would be cleaner with a dependency injection framework,
    // but for simplicity, we'll recreate the dependencies here.
    final apiClient = ApiClient();
    final syncRepository = SyncRepository(apiClient);
    final emulatorRepository = EmulatorRepository();
    final pathService = SystemPathService(emulatorRepository);
    final syncService = SyncService(syncRepository, pathService);

    try {
      if (task == "uploadTask") {
        final systemId = inputData?['systemId'] as String?;
        final gameId = inputData?['gameId'] as String?;

        if (systemId != null && gameId != null) {
          final basePath = await syncService.getSystemBasePath(systemId, gameId: gameId);
          if (basePath != null) {
             final filter = syncService.getFilterForGame(systemId, gameId);
             // Background upload after game close: still use full check to be safe
             await syncRepository.syncSystem(systemId, basePath, onProgress: (msg) {
                print("Background Upload: $msg");
             }, filenameFilter: filter);
          }
        }
      } else if (task == "periodicSync") {
        // Periodic background check: use fastSync to save battery
        print("Starting battery-efficient periodic sync...");
        await syncService.runSync(
          fastSync: true,
          onProgress: (msg) {
            print("Periodic Sync: $msg");
          }
        );
      } else {
        // Generic full sync
        await syncService.runSync(onProgress: (msg) {
          print("Background Sync: $msg");
        });
      }
      return Future.value(true);
    } catch (e) {
      print("Background Sync Error: $e");
      return Future.value(false);
    }
  });
}