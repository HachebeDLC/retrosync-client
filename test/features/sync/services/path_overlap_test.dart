import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vaultsync_client/features/emulation/data/emulator_repository.dart';
import 'package:vaultsync_client/features/emulation/domain/emulator_config.dart';
import 'package:vaultsync_client/features/sync/services/system_path_service.dart';

class _MockEmulatorRepository extends Mock implements EmulatorRepository {}

EmulatorConfig _stubSystem(String id) {
  return EmulatorConfig(
    system: SystemInfo(
      id: id,
      name: id.toUpperCase(),
      folders: const [],
      extensions: const [],
      ignoredFolders: const [],
    ),
    emulators: const [],
  );
}

// Pins the path-overlap detection logic so two systems can't silently end up
// sharing a save folder — the cause of the cross-namespace duplication seen
// on the server (gc/, nds/, ps1/ all containing the same files).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SystemPathService service;
  late _MockEmulatorRepository repo;

  setUp(() {
    repo = _MockEmulatorRepository();
    when(() => repo.loadSystems()).thenAnswer((_) async => [
          _stubSystem('gc'),
          _stubSystem('nds'),
          _stubSystem('ps1'),
          _stubSystem('retroarch'),
        ]);
  });

  Future<void> seed(Map<String, String> paths) async {
    SharedPreferences.setMockInitialValues({
      for (final e in paths.entries) 'system_path_${e.key}': e.value,
    });
    service = SystemPathService(repo);
  }

  group('findPathConflicts', () {
    test('flags an exact path match under a different system', () async {
      await seed({'gc': '/storage/saves'});
      final result = await service.findPathConflicts('nds', '/storage/saves');
      expect(result, ['gc']);
    });

    test('flags multiple conflicting systems', () async {
      await seed({'gc': '/storage/saves', 'ps1': '/storage/saves'});
      final result = await service.findPathConflicts('nds', '/storage/saves');
      expect(result, containsAll(['gc', 'ps1']));
      expect(result, hasLength(2));
    });

    test('flags child path (candidate sits inside an existing system path)', () async {
      await seed({'gc': '/storage/saves'});
      final result = await service.findPathConflicts('nds', '/storage/saves/GC');
      expect(result, ['gc']);
    });

    test('flags parent path (candidate contains an existing system path)', () async {
      await seed({'gc': '/storage/saves/GC'});
      final result = await service.findPathConflicts('nds', '/storage/saves');
      expect(result, ['gc']);
    });

    test('ignores the system being edited (self-edit is safe)', () async {
      await seed({'gc': '/storage/saves'});
      final result = await service.findPathConflicts('gc', '/storage/saves');
      expect(result, isEmpty);
    });

    test('is case-insensitive on the system id', () async {
      await seed({'gc': '/storage/saves'});
      final result = await service.findPathConflicts('GC', '/storage/saves');
      expect(result, isEmpty);
    });

    test('normalizes trailing slashes', () async {
      await seed({'gc': '/storage/saves/'});
      final result = await service.findPathConflicts('nds', '/storage/saves');
      expect(result, ['gc']);
    });

    test('does not treat sibling paths as overlapping', () async {
      // /foo and /foobar should NOT collide just because of a prefix match.
      await seed({'gc': '/storage/saves'});
      final result = await service.findPathConflicts('nds', '/storage/savestate');
      expect(result, isEmpty);
    });

    test('returns empty when no other systems are configured', () async {
      await seed({});
      final result = await service.findPathConflicts('gc', '/storage/saves');
      expect(result, isEmpty);
    });

    test('ignores empty candidate path', () async {
      await seed({'gc': '/storage/saves'});
      final result = await service.findPathConflicts('nds', '');
      expect(result, isEmpty);
    });
  });
}
