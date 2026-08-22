import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vaultsync_client/features/sync/data/sync_repository.dart';
import 'package:vaultsync_client/features/sync/data/switch_profile_resolver.dart';
import 'package:vaultsync_client/features/sync/data/sync_diff_service.dart';
import 'package:vaultsync_client/features/sync/data/sync_job_queue.dart';
import 'package:vaultsync_client/features/sync/services/system_path_service.dart';
import 'package:vaultsync_client/features/sync/data/file_cache.dart';
import 'package:vaultsync_client/core/services/api_client.dart';
import 'package:vaultsync_client/features/sync/services/sync_network_service.dart';
import 'package:vaultsync_client/features/sync/services/sync_path_resolver.dart';
import 'package:vaultsync_client/features/sync/data/sync_state_database.dart';
import 'package:vaultsync_client/features/sync/services/file_hash_service.dart';
import 'package:vaultsync_client/features/sync/services/conflict_resolver.dart';

class MockApiClient extends Mock implements ApiClient {}
class MockSystemPathService extends Mock implements SystemPathService {}
class MockFileCache extends Mock implements FileCache {}
class MockSyncNetworkService extends Mock implements SyncNetworkService {}
class MockSyncPathResolver extends Mock implements SyncPathResolver {}
class MockSyncStateDatabase extends Mock implements SyncStateDatabase {}
class MockFileHashService extends Mock implements FileHashService {}
class MockConflictResolver extends Mock implements ConflictResolver {}
class MockSwitchProfileResolver extends Mock implements SwitchProfileResolver {}
class MockSyncDiffService extends Mock implements SyncDiffService {}
class MockSyncJobQueue extends Mock implements SyncJobQueue {}

// Subclass to mock internal protected method
class TestSyncRepository extends SyncRepository {
  String mockDeviceName = 'TestDevice';

  TestSyncRepository(
    super.apiClient, 
    super.pathService, 
    super.fileCache, 
    super.networkService, 
    super.pathResolver, 
    super.syncStateDb,
    super.hashService,
    super.conflictResolver,
    super.switchResolver,
    super.diffService,
    super.jobQueue,
    super.ref,
  );

  @override
  Future<String> getDeviceNameInternal() async => mockDeviceName;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  
  late TestSyncRepository repository;
  late MockApiClient mockApiClient;
  late MockSystemPathService mockPathService;
  late MockFileCache mockFileCache;
  late MockSyncNetworkService mockNetworkService;
  late MockSyncPathResolver mockPathResolver;
  late MockSyncStateDatabase mockSyncStateDb;
  late MockFileHashService mockFileHashService;
  late MockConflictResolver mockConflictResolver;
  late MockSwitchProfileResolver mockSwitchResolver;
  late MockSyncDiffService mockSyncDiffService;
  late MockSyncJobQueue mockSyncJobQueue;

  setUp(() {
    mockApiClient = MockApiClient();
    mockPathService = MockSystemPathService();
    mockFileCache = MockFileCache();
    mockNetworkService = MockSyncNetworkService();
    mockPathResolver = MockSyncPathResolver();
    mockSyncStateDb = MockSyncStateDatabase();
    mockFileHashService = MockFileHashService();
    mockConflictResolver = MockConflictResolver();
    mockSwitchResolver = MockSwitchProfileResolver();
    mockSyncDiffService = MockSyncDiffService();
    mockSyncJobQueue = MockSyncJobQueue();
    
    repository = TestSyncRepository(
      mockApiClient, 
      mockPathService, 
      mockFileCache, 
      mockNetworkService, 
      mockPathResolver, 
      mockSyncStateDb,
      mockFileHashService,
      mockConflictResolver,
      mockSwitchResolver,
      mockSyncDiffService,
      mockSyncJobQueue,
      null,
    );
    
    registerFallbackValue(<String, dynamic>{});
  });

  // handleRemoteEvent no longer queues the download itself. It reports which
  // system a remote change affects and SyncEventService runs a real per-system
  // sync for it after coalescing the burst.
  //
  // The old design resolved the destination here using `_lastScanList`, which is
  // only populated by a scan — before the first sync of a session it was empty,
  // so the same file resolved to a different path than a real sync would. Worse,
  // nothing ever drained the queue it wrote: the user got a "New save available"
  // notification and no download until they synced manually.
  //
  // These tests assert the return value rather than the absence of an
  // upsertState call: nothing calls upsertState from this path any more, so a
  // verifyNever would pass no matter what the code did.
  group('SyncRepository Remote Events', () {
    test('reports the system to sync for a configured system', () async {
      final payload = {
        'path': 'ps2/memcards/game.ps2',
        'system_id': 'ps2',
        'origin_device': 'OtherHandheld',
        'hash': 'remotehash123',
        'size': 8388608,
        'updated_at': 1679572800000,
      };

      when(() => mockPathService.getAllSystemPaths()).thenAnswer((_) async => {'ps2': '/storage/ps2'});

      expect(await repository.handleRemoteEvent(payload), 'ps2');
    });

    test('does not resolve paths or touch the transfer queue', () async {
      final payload = {
        'path': 'ps2/memcards/game.ps2',
        'system_id': 'ps2',
        'origin_device': 'OtherHandheld',
        'hash': 'remotehash123',
        'size': 8388608,
        'updated_at': 1679572800000,
      };

      when(() => mockPathService.getAllSystemPaths()).thenAnswer((_) async => {'ps2': '/storage/ps2'});

      await repository.handleRemoteEvent(payload);

      // Path resolution belongs to the sync that follows, where a scan has run.
      verifyNever(() => mockPathResolver.getLocalRelPath(any(), any(), any(), any()));
      verifyNever(() => mockSyncStateDb.upsertState(any(), any(), any(), any(), any(),
            systemId: any(named: 'systemId'),
            remotePath: any(named: 'remotePath'),
            relPath: any(named: 'relPath'),
            blockHashes: any(named: 'blockHashes')));
    });

    test('ignores events echoed back from this device', () async {
      repository.mockDeviceName = 'MyDevice';

      final payload = {
        'path': 'ps2/memcards/game.ps2',
        'system_id': 'ps2',
        'origin_device': 'MyDevice',
        'hash': 'remotehash123',
        'size': 8388608,
        'updated_at': 1679572800000,
      };

      expect(await repository.handleRemoteEvent(payload), isNull);
      verifyNever(() => mockPathService.getAllSystemPaths());
    });

    test('ignores events for systems this device has not configured', () async {
      final payload = {
        'path': 'switch/saves/0100.sav',
        'system_id': 'switch',
        'origin_device': 'OtherDevice',
        'hash': 'remotehash123',
        'size': 1024,
        'updated_at': 1679572800000,
      };

      when(() => mockPathService.getAllSystemPaths()).thenAnswer((_) async => {'ps2': '/storage/ps2'});

      expect(await repository.handleRemoteEvent(payload), isNull);
    });
  });
}
