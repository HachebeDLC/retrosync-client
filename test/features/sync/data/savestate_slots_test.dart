import 'package:flutter_test/flutter_test.dart';
import 'package:vaultsync_client/features/sync/data/dart_file_scanner.dart';

// RetroArch writes manual savestates as `<rom>.state1`, `.state2`, … ; slot 0
// is plain `.state` and the automatic one ends in `.state.auto`. Only `state`
// and `auto` are listed in the per-system save_extensions, so every manual
// slot was skipped without a word — an Emerald `.state1` sat on the device for
// a day and never reached the server.
void main() {
  group('normaliseSaveExtension', () {
    test('numbered slots collapse onto state', () {
      for (final n in [0, 1, 2, 9, 10, 99]) {
        expect(DartFileScanner.normaliseSaveExtension('state$n'), 'state',
            reason: 'state$n should be treated as a savestate');
      }
    });

    test('plain state and auto are untouched', () {
      expect(DartFileScanner.normaliseSaveExtension('state'), 'state');
      expect(DartFileScanner.normaliseSaveExtension('auto'), 'auto');
    });

    test('it does not swallow unrelated extensions that start with state', () {
      // Only digits qualify; anything else keeps its own identity so it still
      // has to earn a place in save_extensions on its own.
      expect(DartFileScanner.normaliseSaveExtension('statex'), 'statex');
      expect(DartFileScanner.normaliseSaveExtension('states'), 'states');
      expect(DartFileScanner.normaliseSaveExtension('state1a'), 'state1a');
      expect(DartFileScanner.normaliseSaveExtension(''), '');
    });
  });

  group('shouldSyncFile', () {
    test('a manual slot is now synced for a system that allows state', () {
      // This is the regression.
      expect(
        DartFileScanner.shouldSyncFile(
          'gba',
          'states/Pokemon - Emerald Version (USA, Europe).state1',
          'Pokemon - Emerald Version (USA, Europe).state1',
          saveExtensions: const {'sav', 'srm', 'state', 'auto', 'rtc'},
        ),
        isTrue,
      );
    });

    test('slot 0 and the auto state keep working', () {
      const exts = {'sav', 'srm', 'state', 'auto', 'rtc'};
      expect(
        DartFileScanner.shouldSyncFile('gba', 'states/Game.state', 'Game.state',
            saveExtensions: exts),
        isTrue,
      );
      expect(
        DartFileScanner.shouldSyncFile(
            'gba', 'states/Game.state.auto', 'Game.state.auto',
            saveExtensions: exts),
        isTrue,
      );
    });

    test('a system that does not allow states still rejects the slot', () {
      expect(
        DartFileScanner.shouldSyncFile('nds', 'Game.state1', 'Game.state1',
            saveExtensions: const {'sav', 'dsv'}),
        isFalse,
      );
    });
  });
}
