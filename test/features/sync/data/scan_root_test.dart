import 'package:flutter_test/flutter_test.dart';
import 'package:vaultsync_client/features/sync/data/sync_repository.dart';

// Pins the resolution that made the RetroArch root fix a no-op.
//
// `syncSystem`/`diffSystem` receive the CLOUD NAMESPACE as `systemId`, not the
// configured system: gba, snes, n64 and ps1 all arrive as `RetroArch`. They
// then re-resolved the scan root from that name — a key no user ever sets — so
// the lookup fell through to `suggestSavePath`'s hardcoded
// `/storage/emulated/0/RetroArch/saves`, silently discarding the root the
// caller had already resolved.
//
// Observed on 2026-08-22: after the four systems were correctly lifted to
// `/storage/emulated/0/RetroArch`, the native scanner still logged
//   "SCAN: Starting Local Recursive Scan for RetroArch at .../RetroArch/saves"
// so `states/` was never walked. Not one savestate on that device had ever been
// backed up: every `RetroArch/states/*` row on the server came from a handheld
// retired in March.
void main() {
  group('pickScanRoot', () {
    test("the caller's resolved root wins over the fallback", () {
      // This is the regression: before the fix the fallback always won.
      expect(
        SyncRepository.pickScanRoot(
          '/storage/emulated/0/RetroArch',
          '/storage/emulated/0/RetroArch/saves',
        ),
        '/storage/emulated/0/RetroArch',
      );
    });

    test('the fallback is used only when no root was passed', () {
      expect(
        SyncRepository.pickScanRoot('', '/storage/emulated/0/RetroArch/saves'),
        '/storage/emulated/0/RetroArch/saves',
      );
    });

    test('a SAF root passes through untouched', () {
      // Systems under /Android/data arrive as tree URIs; rewriting or
      // re-resolving one loses the grant it was issued against.
      const saf =
          'content://com.android.externalstorage.documents/tree/primary%3AAndroid%2Fdata%2Fme.magnum.melonds';
      expect(SyncRepository.pickScanRoot(saf, '/fallback'), saf);
    });

    test('a shizuku root passes through untouched', () {
      const shizuku = 'shizuku:///storage/emulated/0/RetroArch';
      expect(SyncRepository.pickScanRoot(shizuku, '/fallback'), shizuku);
    });
  });
}
