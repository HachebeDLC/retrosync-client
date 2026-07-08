import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:vaultsync_client/features/sync/services/background_sync_service.dart';
import 'package:vaultsync_client/features/sync/services/sync_service.dart';
import 'package:vaultsync_client/features/sync/services/system_path_service.dart';

class MockSyncService extends Mock implements SyncService {}

class MockSystemPathService extends Mock implements SystemPathService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BackgroundSyncService service;
  late MockSyncService mockSyncService;
  late MockSystemPathService mockPathService;

  setUp(() {
    mockSyncService = MockSyncService();
    mockPathService = MockSystemPathService();
    service = BackgroundSyncService(mockSyncService, mockPathService);
  });

  test('startMonitoring should be callable', () async {
    // This is hard to verify with MethodChannels in unit tests without a mock channel,
    // but we can at least verify the method exists and doesn't crash on non-android.
    await service.startMonitoring();
  });

  test('stopMonitoring should be callable', () async {
    await service.stopMonitoring();
  });

  test('PS2 package map covers AetherSX2, NetherSX2, and Turnip builds', () {
    expect(
        BackgroundSyncService.packageToSystem['xyz.aethersx2.android'], 'ps2');
    expect(
        BackgroundSyncService.packageToSystem['xyz.nethersx2.android'], 'ps2');
    expect(
        BackgroundSyncService.packageToSystem['xyz.aethersx2.custom'], 'ps2');
    expect(
        BackgroundSyncService.packageToSystem['xyz.aethersx2.tturnip'], 'ps2');
  });

  test('PS2 assets include NetherSX2-Turnip and its Android data root',
      () async {
    final ps2Raw = await rootBundle.loadString('assets/systems/ps2.json');
    final ps2 = json.decode(ps2Raw) as Map<String, dynamic>;
    final emulators = (ps2['emulators'] as List).cast<Map<String, dynamic>>();

    expect(
      emulators.any((e) => e['unique_id'] == 'ps2.xyz.aethersx2.tturnip'),
      isTrue,
    );

    final configRaw =
        await rootBundle.loadString('assets/config/path_config.json');
    final config = json.decode(configRaw) as Map<String, dynamic>;
    final defaults = config['standaloneDefaults'] as Map<String, dynamic>;

    expect(
      defaults['xyz.aethersx2.tturnip'],
      '/storage/emulated/0/Android/data/xyz.aethersx2.tturnip/files',
    );
  });
}
