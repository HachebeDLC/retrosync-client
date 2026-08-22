import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vaultsync_client/features/emulation/data/emulator_repository.dart';
import 'package:vaultsync_client/features/sync/services/system_path_service.dart';

class _MockEmulatorRepository extends Mock implements EmulatorRepository {}

// Covers `pathExists`, the check that turns an auto-suggested save path from a
// guess into something verified.
//
// It matters because `suggestSavePath` never confirms the folder is real: there
// are only 21 entries in path_config.json's standaloneDefaults against 133
// systems in assets/systems, and everything else falls through to the hardcoded
// '/storage/emulated/0/RetroArch/saves'. Without this check a setup can look
// complete and then sync nothing.
//
// On Android the call routes to the native `checkPathExists` (which can see
// inside /Android/data, where dart:io throws); on the host it falls back to
// dart:io, which is what these tests exercise with real directories.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SystemPathService service;
  late Directory tempDir;

  setUp(() async {
    final repo = _MockEmulatorRepository();
    when(() => repo.loadSystems()).thenAnswer((_) async => []);
    SharedPreferences.setMockInitialValues({});
    service = SystemPathService(repo);
    tempDir = await Directory.systemTemp.createTemp('vaultsync_paths');
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  test('reports true for a directory that exists', () async {
    expect(await service.pathExists(tempDir.path), isTrue);
  });

  test('reports false for a directory that does not exist', () async {
    final missing = '${tempDir.path}/Android/data/xyz.aethersx2.android/files';
    expect(await service.pathExists(missing), isFalse);
  });

  test('reports true once the directory is created', () async {
    final target = Directory('${tempDir.path}/ps2/memcards');
    expect(await service.pathExists(target.path), isFalse);
    await target.create(recursive: true);
    expect(await service.pathExists(target.path), isTrue);
  });
}
