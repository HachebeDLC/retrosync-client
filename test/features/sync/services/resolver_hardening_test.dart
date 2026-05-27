import 'package:flutter_test/flutter_test.dart';
import 'package:vaultsync_client/features/sync/services/sync_path_resolver.dart';

// Regression tests for patterns observed in real server data
// (psp/ root flattened files, wii/.../content/*.app NAND blobs).
// Each test pins a "this can no longer be uploaded" invariant.
void main() {
  late SyncPathResolver resolver;

  setUp(() {
    resolver = SyncPathResolver();
  });

  group('PSP hardening', () {
    test('flat file with no SAVEDATA/PPSSPP_STATE anchor is skipped', () {
      expect(resolver.getCloudRelPath('psp', 'ULJM05775_PARAM.SFO'), '');
      expect(resolver.getCloudRelPath('psp', 'ICON0.PNG'), '');
      expect(resolver.getCloudRelPath('ppsspp', 'NPUG80329DATA00_PARAM.SFO'), '');
    });

    test('legitimate SAVEDATA paths still resolve', () {
      expect(
        resolver.getCloudRelPath('psp', 'SAVEDATA/ULJM05775/PARAM.SFO'),
        'SAVEDATA/ULJM05775/PARAM.SFO',
      );
      expect(
        resolver.getCloudRelPath('psp', 'PPSSPP_STATE/ULJM05775_1.00_0.ppst'),
        'PPSSPP_STATE/ULJM05775_1.00_0.ppst',
      );
    });

    test('probed gameId still wins over the skip', () {
      expect(
        resolver.getCloudRelPath('psp', 'ULJM05775_PARAM.SFO',
            probedMetadata: {'gameId': 'ULJM05775'}),
        'SAVEDATA/ULJM05775',
      );
    });
  });

  group('Wii NAND content denylist', () {
    test('Wii .app content blobs are skipped', () {
      expect(
        resolver.getCloudRelPath('wii', 'title/00010000/52334d45/content/0000000a.app'),
        '',
      );
    });

    test('Wii .tmd title metadata is skipped', () {
      expect(
        resolver.getCloudRelPath('wii', 'title/00010000/52334d45/content/title.tmd'),
        '',
      );
    });

    test('Wii .wad install package is skipped', () {
      expect(resolver.getCloudRelPath('wii', 'Channel.wad'), '');
    });

    test('Same denylist applies under sid=dolphin', () {
      expect(
        resolver.getCloudRelPath('dolphin', 'Wii/title/00010000/52334d45/content/0000000a.app'),
        '',
      );
    });

    test('Same denylist applies under sid=gc', () {
      // Edge case: user pointing GC system at a Wii NAND mount.
      expect(resolver.getCloudRelPath('gc', 'title.tmd'), '');
    });

    test('Legitimate Wii saves still resolve', () {
      expect(
        resolver.getCloudRelPath('wii', 'title/00010000/52334d45/data/save.bin'),
        '00010000/52334d45/data/save.bin',
      );
    });
  });

  group('RetroArch .bak rejection', () {
    // RetroArch rotates the previous save to `.bak` on every write.
    // These are local-only backups and must never reach the cloud.
    test('.srm.bak at scan root is skipped', () {
      expect(resolver.getCloudRelPath('retroarch', 'Pokemon Emerald.srm.bak'), '');
    });

    test('.state.auto.bak at scan root is skipped', () {
      expect(resolver.getCloudRelPath('retroarch', 'Mega Man X.state.auto.bak'), '');
    });

    test('.bak under saves/ anchor is skipped (was passing through)', () {
      expect(
        resolver.getCloudRelPath('retroarch', 'saves/mGBA/Apotris.srm.bak'),
        '',
      );
    });

    test('.bak under states/ anchor is skipped (was passing through)', () {
      expect(
        resolver.getCloudRelPath('retroarch', 'states/Snes9x/Chrono Trigger.state.auto.bak'),
        '',
      );
    });

    test('.bak under a per-core subdir is skipped', () {
      expect(
        resolver.getCloudRelPath('retroarch', 'mGBA/Apotris.srm.bak'),
        '',
      );
    });

    test('legitimate .srm/.state.auto still resolve', () {
      expect(
        resolver.getCloudRelPath('retroarch', 'saves/mGBA/Apotris.srm'),
        'saves/mGBA/Apotris.srm',
      );
      expect(
        resolver.getCloudRelPath('retroarch', 'states/Snes9x/Chrono Trigger.state.auto'),
        'states/Snes9x/Chrono Trigger.state.auto',
      );
    });

    test('Case-insensitive on extension (.BAK rejected too)', () {
      expect(resolver.getCloudRelPath('retroarch', 'saves/mGBA/Apotris.SRM.BAK'), '');
    });
  });
}
