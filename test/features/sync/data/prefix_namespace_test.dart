import 'package:flutter_test/flutter_test.dart';
import 'package:vaultsync_client/features/sync/data/sync_diff_service.dart';

// The server filters the file list with `path ILIKE '<prefix>%'` — no
// delimiter (vaultsync_server/app/crud.py). Any namespace that is a string
// prefix of another therefore swallows it.
//
// Observed on 2026-08-22: syncing `wii` pulled in the `wiiu/` namespace, a
// Cemu backup from a Linux machine. The Wii resolver mapped those rows to
// `title/wiiu/…` inside Dolphin's folder, and the download aborted the whole
// sync with "expected 1027208 bytes, got 1027325" — the size came from the row
// it asked for, the bytes from the row it actually got.
List<Map<String, dynamic>> rows(List<String> paths) =>
    [for (final p in paths) {'path': p, 'size': 1}];

void main() {
  group('filterToPrefix', () {
    test('drops a namespace that merely starts with the same letters', () {
      final result = SyncDiffService.filterToPrefix(
        rows([
          'wii/00010000/52334d45/data/save.bin',
          'wiiu/00050000/101c9500/user/80000001/4/game_data.sav',
        ]),
        'wii',
      );

      expect(result.map((r) => r['path']),
          ['wii/00010000/52334d45/data/save.bin']);
    });

    test('keeps everything genuinely under the namespace', () {
      final paths = [
        'wii/00010000/52334d45/data/save.bin',
        'wii/00010000/524b4450/data/save.dat',
      ];
      expect(
        SyncDiffService.filterToPrefix(rows(paths), 'wii').length,
        paths.length,
      );
    });

    test('matches the segment case-insensitively', () {
      // The RetroArch namespace is stored capitalised but requested lowercase
      // in places, so the comparison cannot be case-sensitive.
      final result = SyncDiffService.filterToPrefix(
        rows(['RetroArch/saves/Pokemon - Emerald Version (USA, Europe).srm']),
        'retroarch',
      );
      expect(result, hasLength(1));
    });

    test('tolerates a prefix given with a trailing slash', () {
      final result = SyncDiffService.filterToPrefix(
        rows(['wii/a.bin', 'wiiu/b.sav']),
        'wii/',
      );
      expect(result.map((r) => r['path']), ['wii/a.bin']);
    });

    test('does not drop the namespace row itself', () {
      final result = SyncDiffService.filterToPrefix(rows(['wii']), 'wii');
      expect(result, hasLength(1));
    });

    test('an empty prefix asks for everything and filters nothing', () {
      final all = rows(['wii/a.bin', 'ps2/b.bin']);
      expect(SyncDiffService.filterToPrefix(all, ''), hasLength(2));
    });

    test('skips malformed rows instead of throwing', () {
      final result = SyncDiffService.filterToPrefix(
        [
          {'path': 'wii/a.bin'},
          {'size': 10},
          'not a map',
        ],
        'wii',
      );
      expect(result, hasLength(1));
    });

    test('the other namespaces in this vault are unaffected', () {
      // ps1/ps2 and nds/3ds do not clash, but pin it so a future rename that
      // introduces a clash fails here rather than on a device.
      final all = rows([
        'ps1/Wii/title/00010000/x.sav',
        'ps2/memcards/y.bin',
        'nds/files/saves/z.sav',
        '3ds/saves/w.sav',
      ]);
      expect(SyncDiffService.filterToPrefix(all, 'ps1').map((r) => r['path']),
          ['ps1/Wii/title/00010000/x.sav']);
      expect(SyncDiffService.filterToPrefix(all, 'ps2').map((r) => r['path']),
          ['ps2/memcards/y.bin']);
      expect(SyncDiffService.filterToPrefix(all, 'nds').map((r) => r['path']),
          ['nds/files/saves/z.sav']);
    });
  });
}
