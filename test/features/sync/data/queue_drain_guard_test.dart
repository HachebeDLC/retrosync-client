import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vaultsync_client/features/sync/data/sync_job_queue.dart';
import 'package:vaultsync_client/features/sync/data/sync_state_database.dart';
import 'package:vaultsync_client/features/sync/services/sync_network_service.dart';
import 'package:vaultsync_client/features/sync/services/system_path_service.dart';

class MockSyncStateDatabase extends Mock implements SyncStateDatabase {}

class MockSyncNetworkService extends Mock implements SyncNetworkService {}

class MockSystemPathService extends Mock implements SystemPathService {}

// Pins the re-entrancy guard on the transfer queue.
//
// `getPendingJobs()` is a plain SELECT with no claim column and no row locking,
// so two overlapping drains read the same rows and transfer the same file twice.
// That was unreachable while nothing drained the queue at all — the WorkManager
// `processQueue` task only re-registered itself, and LifecycleSyncService was
// never instantiated. With those reconnected there are now four live triggers
// (worker, SSE flush, app resume, online recovery), so overlap is reachable.
//
// The guard is deliberately per-isolate. The WorkManager worker builds its own
// ProviderContainer and therefore its own SyncJobQueue, so it cannot see this
// flag; that gap needs a claim column in `sync_state` and is not covered here.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockSyncStateDatabase db;
  late SyncJobQueue queue;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = MockSyncStateDatabase();
    queue = SyncJobQueue(db, MockSyncNetworkService(), MockSystemPathService());
  });

  Future<void> drain() => queue.processManual(
        getDeviceName: () async => 'TestDevice',
        recordSyncSuccess: (_, __, ___, ____, _____) {},
        getMasterKey: () async => null,
      );

  test('a drain requested mid-flight does not start a second pass', () async {
    final gate = Completer<List<Map<String, dynamic>>>();
    var queries = 0;
    when(() => db.getPendingJobs()).thenAnswer((_) {
      queries++;
      return queries == 1 ? gate.future : Future.value(<Map<String, dynamic>>[]);
    });

    final first = drain();
    await Future<void>.delayed(Duration.zero); // let the first drain reach the await

    await drain(); // must return immediately, not run concurrently
    expect(queries, 1, reason: 'the second call started its own pass');

    gate.complete(<Map<String, dynamic>>[]);
    await first;

    expect(queries, 2, reason: 'the deferred request should re-run exactly once');
  });

  test('repeats only once no matter how many requests arrive mid-flight', () async {
    final gate = Completer<List<Map<String, dynamic>>>();
    var queries = 0;
    when(() => db.getPendingJobs()).thenAnswer((_) {
      queries++;
      return queries == 1 ? gate.future : Future.value(<Map<String, dynamic>>[]);
    });

    final first = drain();
    await Future<void>.delayed(Duration.zero);

    await drain();
    await drain();
    await drain();

    gate.complete(<Map<String, dynamic>>[]);
    await first;

    // Four requests total collapse into two passes: the original and one repeat.
    expect(queries, 2);
  });

  test('a later drain runs normally once the guard has been released', () async {
    when(() => db.getPendingJobs())
        .thenAnswer((_) async => <Map<String, dynamic>>[]);

    await drain();
    await drain();

    verify(() => db.getPendingJobs()).called(2);
  });

  test('the guard is released even when a pass throws', () async {
    var queries = 0;
    when(() => db.getPendingJobs()).thenAnswer((_) {
      queries++;
      if (queries == 1) throw Exception('db unavailable');
      return Future.value(<Map<String, dynamic>>[]);
    });

    await expectLater(drain(), throwsException);

    // Without the finally, _draining would stay true and the queue would never
    // drain again for the lifetime of the process.
    await drain();
    expect(queries, 2);
  });
}
