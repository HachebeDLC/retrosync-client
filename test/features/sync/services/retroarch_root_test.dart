import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultsync_client/features/sync/data/dart_file_scanner.dart';
import 'package:vaultsync_client/features/sync/services/sync_path_resolver.dart';
import 'package:vaultsync_client/features/sync/services/system_path_service.dart';

// Pins the fix for the savestate duplication that kept coming back.
//
// gba, snes, n64 and ps1 were all rooted at `/storage/emulated/0/RetroArch/saves`.
// The cloud namespace for those systems is `RetroArch/`, covering BOTH
// `saves/` and `states/`, so a root inside `saves/` cannot represent it:
//
//   * the scanner never sees `states/`, so savestates are never uploaded — the
//     server's `RetroArch/states/*` rows were all from a device retired in
//     March, and the Nova had never contributed one;
//   * `getLocalRelPath` stripped the anchor off both `saves/x` and `states/x`,
//     so every cloud savestate was written into `saves/`, re-uploaded from
//     there and re-downloaded on the next sync.
//
// A sync run on 2026-08-22 reproduced it exactly: 10 files from
// `RetroArch/states/` landed in `RetroArch/saves/`.
void main() {
  group('liftRetroArchRoot', () {
    test('lifts a root sitting inside RetroArch/saves', () {
      expect(
        SystemPathService.liftRetroArchRoot('/storage/emulated/0/RetroArch/saves'),
        '/storage/emulated/0/RetroArch',
      );
    });

    test('lifts states/ the same way', () {
      expect(
        SystemPathService.liftRetroArchRoot('/storage/emulated/0/RetroArch/states'),
        '/storage/emulated/0/RetroArch',
      );
    });

    test('is case-insensitive on both segments', () {
      expect(
        SystemPathService.liftRetroArchRoot('/storage/emulated/0/retroarch/SAVES'),
        '/storage/emulated/0/retroarch',
      );
    });

    test('tolerates a trailing slash', () {
      expect(
        SystemPathService.liftRetroArchRoot('/storage/emulated/0/RetroArch/saves/'),
        '/storage/emulated/0/RetroArch',
      );
    });

    test('leaves a root already at the RetroArch folder alone', () {
      const root = '/storage/emulated/0/RetroArch';
      expect(SystemPathService.liftRetroArchRoot(root), root);
    });

    test('does not touch a saves folder belonging to another emulator', () {
      // Dolphin, PPSSPP and friends have their own meaning for the last
      // segment; only RetroArch splits one namespace across two siblings.
      const dolphin = '/storage/emulated/0/Android/data/org.dolphinemu.dolphinemu/files/saves';
      expect(SystemPathService.liftRetroArchRoot(dolphin), dolphin);

      const psp = '/storage/emulated/0/PPSSPP/PSP/SAVEDATA';
      expect(SystemPathService.liftRetroArchRoot(psp), psp);
    });

    test('leaves URIs untouched — a SAF grant covers one subtree', () {
      const saf =
          'content://com.android.externalstorage.documents/tree/primary%3ARetroArch%2Fsaves';
      expect(SystemPathService.liftRetroArchRoot(saf), saf);

      const shizuku = 'shizuku:///storage/emulated/0/RetroArch/saves';
      expect(SystemPathService.liftRetroArchRoot(shizuku), shizuku);
    });

    test('handles degenerate input without throwing', () {
      expect(SystemPathService.liftRetroArchRoot(''), '');
      expect(SystemPathService.liftRetroArchRoot('saves'), 'saves');
    });
  });

  group('getLocalRelPath anchors', () {
    final resolver = SyncPathResolver();

    // A scan of a root *inside* saves/ yields bare filenames: no anchor.
    final scanInsideSaves = [
      {'relPath': 'Pokemon - Emerald Version (USA, Europe).srm'},
    ];
    // A scan of the RetroArch folder itself keeps the anchors.
    final scanAtRoot = [
      {'relPath': 'saves/Pokemon - Emerald Version (USA, Europe).srm'},
      {'relPath': 'states/Mega Man X (USA).state.auto'},
    ];

    test('root inside saves/: a cloud save drops its anchor', () {
      expect(
        resolver.getLocalRelPath(
          'gba',
          'RetroArch/saves/Metroid Fusion (USA).srm',
          {},
          scanInsideSaves,
          localRoot: '/storage/emulated/0/RetroArch/saves',
        ),
        'Metroid Fusion (USA).srm',
      );
    });

    test('root inside saves/: a cloud savestate is skipped, not merged', () {
      // This is the regression. Before the fix this returned
      // 'Metroid Fusion (USA).state.auto', writing a savestate into saves/.
      expect(
        resolver.getLocalRelPath(
          'gba',
          'RetroArch/states/Metroid Fusion (USA).state.auto',
          {},
          scanInsideSaves,
          localRoot: '/storage/emulated/0/RetroArch/saves',
        ),
        isNull,
      );
    });

    test('root inside states/: the mirror case is skipped too', () {
      expect(
        resolver.getLocalRelPath(
          'gba',
          'RetroArch/saves/Metroid Fusion (USA).srm',
          {},
          [
            {'relPath': 'Mega Man X (USA).state.auto'},
          ],
          localRoot: '/storage/emulated/0/RetroArch/states',
        ),
        isNull,
      );
    });

    test('root at the RetroArch folder: both anchors are kept', () {
      expect(
        resolver.getLocalRelPath('gba', 'RetroArch/saves/Metroid Fusion (USA).srm',
            {}, scanAtRoot, localRoot: '/storage/emulated/0/RetroArch'),
        'saves/Metroid Fusion (USA).srm',
      );
      expect(
        resolver.getLocalRelPath(
            'gba',
            'RetroArch/states/Metroid Fusion (USA).state.auto',
            {},
            scanAtRoot,
            localRoot: '/storage/emulated/0/RetroArch'),
        'states/Metroid Fusion (USA).state.auto',
      );
    });

    test('empty RetroArch folder: anchors are kept rather than guessed away', () {
      // No files yet, so the scan carries no anchor either. The root is above
      // both folders, so the destination must keep saying which one it is.
      expect(
        resolver.getLocalRelPath('gba', 'RetroArch/states/New.state.auto', {},
            const [], localRoot: '/storage/emulated/0/RetroArch'),
        'states/New.state.auto',
      );
    });

    test('without a root the old anchor-blind behaviour is preserved', () {
      // Older callers and the Switch/PS2 paths still pass no root.
      expect(
        resolver.getLocalRelPath(
            'gba', 'RetroArch/states/New.state.auto', {}, scanInsideSaves),
        'New.state.auto',
      );
    });
  });

  group('scanning the RetroArch folder itself', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('retroarch_root_test');
      Future<void> write(String relPath) async {
        final f = File('${root.path}/$relPath');
        await f.parent.create(recursive: true);
        await f.writeAsString('x');
      }

      await write('saves/Pokemon - Emerald Version (USA, Europe).srm');
      await write('states/Mega Man X (USA).state.auto');
      // Bulk folders. `cheats/` is ~28k files on a stock install, against 27
      // real saves — pruning it is what keeps a root-level scan affordable.
      // The .srm names are deliberate: only a directory-level skip stops them.
      await write('cheats/Nintendo - Game Boy Advance/Metroid.srm');
      await write('thumbnails/Nintendo/Boxarts/Metroid.srm');
      await write('downloads/Metroid.srm');
      await write('assets/xmb/Metroid.srm');
      await write('cores/Metroid.srm');
      await write('database/rdb/Metroid.srm');
      await write('info/Metroid.srm');
      await write('overlays/Metroid.srm');
      await write('filters/Metroid.srm');
      await write('records/Metroid.srm');
      await write('screenshots/Metroid.srm');
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    test('finds both save folders and nothing else', () async {
      final found = await DartFileScanner.scanRecursive(root.path, 'gba', const []);
      final files = found
          .where((f) => f['isDirectory'] != true)
          .map((f) => f['relPath'] as String)
          .toList()
        ..sort();

      expect(files, [
        'saves/Pokemon - Emerald Version (USA, Europe).srm',
        'states/Mega Man X (USA).state.auto',
      ]);
    });

    test('keeps the anchors, so uploads land in the right cloud folder', () async {
      final found = await DartFileScanner.scanRecursive(root.path, 'gba', const []);
      final resolver = SyncPathResolver();

      final state = found.firstWhere(
          (f) => (f['relPath'] as String).endsWith('.state.auto'))['relPath'] as String;
      expect(resolver.getCloudRelPath('gba', state),
          'states/Mega Man X (USA).state.auto');
    });
  });
}
