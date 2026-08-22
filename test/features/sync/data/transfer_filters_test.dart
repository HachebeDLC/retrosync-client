import 'package:flutter_test/flutter_test.dart';
import 'package:vaultsync_client/features/sync/data/dart_file_scanner.dart';

// Pins the two filters that stop VaultSync uploading things that are not saves.
//
// Both were found on the live server after a day of syncing:
//   - 5 `.vstmp` paths, VaultSync's own partial-transfer files (one at 79 MB),
//     written by dart_native_crypto.dart and then scanned back in as saves.
//   - 9 paths under `ps2/.stversions/`, Syncthing's trash directory. The scanner
//     only rejected hidden *files*, so `Mcd002~20231230-160750.ps2` inside a
//     hidden directory passed with an ordinary name.
void main() {
  group('DartFileScanner.shouldSyncFile — transfer noise', () {
    test('rejects VaultSync partial-transfer files', () {
      expect(
        DartFileScanner.shouldSyncFile(
            'ps2', 'memcards/STAGEDAT.PDT.vstmp', 'STAGEDAT.PDT.vstmp'),
        isFalse,
      );
    });

    test('rejects .vstmp even for sync-everything systems', () {
      expect(
        DartFileScanner.shouldSyncFile(
            'switch', 'nand/user/save/x/y/save.dat.vstmp', 'save.dat.vstmp'),
        isFalse,
      );
    });

    test('rejects files inside a hidden directory', () {
      expect(
        DartFileScanner.shouldSyncFile(
            'ps2', '.stversions/Mcd002~20231230-160750.ps2', 'Mcd002~20231230-160750.ps2'),
        isFalse,
      );
    });

    test('rejects a hidden directory nested deeper in the path', () {
      expect(
        DartFileScanner.shouldSyncFile(
            'ps2', 'memcards/.stversions/Mcd001.ps2', 'Mcd001.ps2'),
        isFalse,
      );
    });

    test('rejects hidden dirs for sync-everything systems too', () {
      expect(
        DartFileScanner.shouldSyncFile(
            'switch', 'nand/.trash/0100F2C0115B6000/x.dat', 'x.dat'),
        isFalse,
      );
    });

    test('still accepts a normal save alongside those rules', () {
      expect(
        DartFileScanner.shouldSyncFile('ps2', 'memcards/Mcd001.ps2', 'Mcd001.ps2'),
        isTrue,
      );
    });

    test('does not reject a directory name that merely contains a dot', () {
      expect(
        DartFileScanner.shouldSyncFile(
            'ps2', 'memcards/Total.ps2/data0.bin', 'data0.bin',
            saveExtensions: {'bin'}),
        isTrue,
      );
    });
  });
}
