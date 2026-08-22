import 'package:flutter_test/flutter_test.dart';
import 'package:vaultsync_client/features/sync/services/sync_path_resolver.dart';
import 'package:vaultsync_client/features/sync/services/system_path_service.dart';

// Pins the two guards added after a day of repeatedly cleaning the same
// contamination off a device, off the server, and off a second device.
//
// Neither failure was a resolver bug: in every case the mapping did the right
// thing on top of a wrong local root.
//
//  1. `grantCoversPath` — the SAF picker reopens wherever it was last used, so
//     confirming without navigating grants the previous folder. A grant asked
//     for melonDS came back pointing at Dolphin, and the `nds` system uploaded
//     Dolphin's whole tree under its own namespace (53 paths). The same mistake
//     sent `dc` to the 3DS folder, filling `dc/` with PS2 memory cards.
//
//  2. `dedupeRootSegment` — psp configured at `PPSSPP/PSP/SAVEDATA` instead of
//     `PPSSPP/PSP` made every download land in `PSP/SAVEDATA/SAVEDATA/…`, which
//     was then uploaded back and re-downloaded on the next sync.
void main() {
  group('SystemPathService.grantCoversPath', () {
    const melonds = '/storage/emulated/0/Android/data/me.magnum.melonds/files';
    const dolphin =
        'content://com.android.externalstorage.documents/tree/primary%3AAndroid%2Fdata%2Forg.dolphinemu.dolphinemu%2Ffiles';
    const melondsUri =
        'content://com.android.externalstorage.documents/tree/primary%3AAndroid%2Fdata%2Fme.magnum.melonds%2Ffiles';

    test('accepts a grant for exactly the requested folder', () {
      expect(SystemPathService.grantCoversPath(melonds, melondsUri), isTrue);
    });

    test('accepts a grant for an ancestor, since a tree grant covers children', () {
      const packageRoot =
          'content://com.android.externalstorage.documents/tree/primary%3AAndroid%2Fdata%2Fme.magnum.melonds';
      expect(SystemPathService.grantCoversPath(melonds, packageRoot), isTrue);
    });

    test('rejects the melonDS-asked-for/Dolphin-granted cross', () {
      expect(SystemPathService.grantCoversPath(melonds, dolphin), isFalse);
    });

    test('rejects the dc-asked-for/Azahar-granted cross', () {
      expect(
        SystemPathService.grantCoversPath(
          '/storage/emulated/0/Android/data/com.flycast.emulator/files/data',
          'content://com.android.externalstorage.documents/tree/primary%3AAzahar',
        ),
        isFalse,
      );
    });

    test('rejects a descendant grant: it cannot cover the whole folder', () {
      const deeper =
          'content://com.android.externalstorage.documents/tree/primary%3AAndroid%2Fdata%2Fme.magnum.melonds%2Ffiles%2Fsaves';
      expect(SystemPathService.grantCoversPath(melonds, deeper), isFalse);
    });

    test('rejects a URI it cannot decode rather than assuming it fits', () {
      expect(
        SystemPathService.grantCoversPath(
          melonds,
          'content://com.android.externalstorage.documents/document/primary%3AX',
        ),
        isFalse,
      );
    });

    test('ignores trailing slashes on either side', () {
      expect(SystemPathService.grantCoversPath('$melonds/', melondsUri), isTrue);
    });

    test('does not treat a sibling with a shared prefix as covered', () {
      expect(
        SystemPathService.grantCoversPath(
          '/storage/emulated/0/Android/data/me.magnum.melonds.nightly/files',
          melondsUri,
        ),
        isFalse,
      );
    });
  });

  group('SyncPathResolver.dedupeRootSegment', () {
    test('trims the repeated segment when the root is one level too deep', () {
      expect(
        SyncPathResolver.dedupeRootSegment(
            '/storage/emulated/0/PPSSPP/PSP/SAVEDATA', 'SAVEDATA/ULES01372DAT/PARAM.SFO'),
        'ULES01372DAT/PARAM.SFO',
      );
    });

    test('leaves a correctly configured root untouched', () {
      expect(
        SyncPathResolver.dedupeRootSegment(
            '/storage/emulated/0/PPSSPP/PSP', 'SAVEDATA/ULES01372DAT/PARAM.SFO'),
        'SAVEDATA/ULES01372DAT/PARAM.SFO',
      );
    });

    test('handles the PPSSPP_STATE variant of the same mistake', () {
      expect(
        SyncPathResolver.dedupeRootSegment(
            '/storage/emulated/0/PPSSPP/PSP/PPSSPP_STATE', 'PPSSPP_STATE/load_undo.ppst'),
        'load_undo.ppst',
      );
    });

    test('matches case-insensitively', () {
      expect(
        SyncPathResolver.dedupeRootSegment('/storage/emulated/0/PPSSPP/PSP/savedata',
            'SAVEDATA/ULES01372DAT/PARAM.SFO'),
        'ULES01372DAT/PARAM.SFO',
      );
    });

    test('trims only one segment, never more', () {
      expect(
        SyncPathResolver.dedupeRootSegment(
            '/storage/emulated/0/PPSSPP/PSP/SAVEDATA', 'SAVEDATA/SAVEDATA/x.bin'),
        'SAVEDATA/x.bin',
      );
    });

    test('leaves a single-segment relative path alone', () {
      expect(
        SyncPathResolver.dedupeRootSegment(
            '/storage/emulated/0/Android/data/org.dolphinemu.dolphinemu/files/GC', 'SRAM.raw'),
        'SRAM.raw',
      );
    });

    test('does not trim on a partial segment match', () {
      expect(
        SyncPathResolver.dedupeRootSegment(
            '/storage/emulated/0/PPSSPP/PSP/SAVE', 'SAVEDATA/x.bin'),
        'SAVEDATA/x.bin',
      );
    });

    test('tolerates a trailing slash on the root', () {
      expect(
        SyncPathResolver.dedupeRootSegment(
            '/storage/emulated/0/PPSSPP/PSP/SAVEDATA/', 'SAVEDATA/x.bin'),
        'x.bin',
      );
    });

    test('leaves the switch layout alone', () {
      expect(
        SyncPathResolver.dedupeRootSegment(
            '/storage/emulated/0/Android/data/dev.eden.eden_emulator/files',
            'nand/user/save/0000000000000000/abc/0100F2C0115B6000/x.dat'),
        'nand/user/save/0000000000000000/abc/0100F2C0115B6000/x.dat',
      );
    });
  });
}
