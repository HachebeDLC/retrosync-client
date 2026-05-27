import 'package:flutter_test/flutter_test.dart';
import 'package:vaultsync_client/features/emulation/domain/emulator_config.dart';
import 'package:vaultsync_client/features/sync/data/dart_file_scanner.dart';

// Pins the per-system save-extension behavior + .bak rejection.
// Background: the file scanner whitelisted "bak" and applied one global
// extension list to every system, which let RetroArch .bak rotation files
// and same-named saves from foreign systems both leak into uploads.
void main() {
  group('DartFileScanner.shouldSyncFile — .bak rejection', () {
    test('rejects .bak under any system', () {
      expect(DartFileScanner.shouldSyncFile('snes', 'Pokemon.srm.bak',
          'Pokemon.srm.bak'), isFalse);
      expect(DartFileScanner.shouldSyncFile('gc', 'foo.gci.bak', 'foo.gci.bak'),
          isFalse);
      expect(DartFileScanner.shouldSyncFile('switch', 'foo.bak', 'foo.bak'),
          isFalse);
    });

    test('rejects .BAK (case-insensitive)', () {
      expect(DartFileScanner.shouldSyncFile('snes', 'Pokemon.SRM.BAK',
          'Pokemon.SRM.BAK'), isFalse);
    });

    test('.bak rejected even when explicitly listed in saveExtensions', () {
      // Defense in depth — a system JSON that accidentally lists "bak" must
      // still be denied.
      expect(
        DartFileScanner.shouldSyncFile(
          'snes', 'Pokemon.bak', 'Pokemon.bak',
          saveExtensions: {'bak', 'srm'},
        ),
        isFalse,
      );
    });
  });

  group('DartFileScanner.shouldSyncFile — per-system allowlist', () {
    test('GC accepts .gci/.raw/.sav', () {
      const allow = {'gci', 'raw', 'sav'};
      expect(DartFileScanner.shouldSyncFile('gc', 'foo.gci', 'foo.gci',
          saveExtensions: allow), isTrue);
      expect(DartFileScanner.shouldSyncFile('gc', 'foo.raw', 'foo.raw',
          saveExtensions: allow), isTrue);
      expect(DartFileScanner.shouldSyncFile('gc', 'foo.sav', 'foo.sav',
          saveExtensions: allow), isTrue);
    });

    test('GC rejects .ps2 (foreign content)', () {
      const allow = {'gci', 'raw', 'sav'};
      expect(DartFileScanner.shouldSyncFile('gc', 'memcard.ps2', 'memcard.ps2',
          saveExtensions: allow), isFalse);
    });

    test('PS1 rejects .srm when allowlist is mcd/mcr/mcx/mc', () {
      // A user pointing PS1 at a RetroArch saves folder would previously
      // upload .srm files into the ps1/ namespace. The per-system list
      // now refuses them.
      const allow = {'mcd', 'mcr', 'mcx', 'mc'};
      expect(DartFileScanner.shouldSyncFile('ps1', 'Tekken 3.srm',
          'Tekken 3.srm', saveExtensions: allow), isFalse);
    });

    test('Empty saveExtensions falls back to global set', () {
      // Sanity: with no per-system list, the global allowlist applies.
      expect(DartFileScanner.shouldSyncFile('snes', 'foo.srm', 'foo.srm'),
          isTrue);
      // And the global set excludes .bak.
      expect(DartFileScanner.shouldSyncFile('snes', 'foo.bak', 'foo.bak'),
          isFalse);
    });

    test('Global set is the curated default', () {
      // Spot-check: the curated default contains srm/state/auto and
      // explicitly omits "bak".
      expect(DartFileScanner.globalSaveExtensions.contains('srm'), isTrue);
      expect(DartFileScanner.globalSaveExtensions.contains('state'), isTrue);
      expect(DartFileScanner.globalSaveExtensions.contains('auto'), isTrue);
      expect(DartFileScanner.globalSaveExtensions.contains('bak'), isFalse);
    });
  });

  group('SystemInfo.fromJson parses save_extensions', () {
    test('reads save_extensions field when present', () {
      final info = SystemInfo.fromJson({
        'id': 'gc',
        'name': 'GameCube',
        'folders': <String>[],
        'extensions': <String>[],
        'ignored_folders': <String>[],
        'save_extensions': ['gci', 'raw', 'sav'],
      });
      expect(info.saveExtensions, ['gci', 'raw', 'sav']);
    });

    test('defaults to empty when save_extensions missing', () {
      final info = SystemInfo.fromJson({
        'id': 'unknown',
        'name': 'Unknown',
        'folders': <String>[],
        'extensions': <String>[],
        'ignored_folders': <String>[],
      });
      expect(info.saveExtensions, isEmpty);
    });
  });
}
