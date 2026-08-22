import 'package:flutter_test/flutter_test.dart';
import 'package:vaultsync_client/features/sync/services/system_path_service.dart';

// Pins the SAF-vs-POSIX-vs-Shizuku decision and the path normalisation it relies
// on.
//
// The regression that motivated these tests: `safNeededFor` used to test the RAW
// stored value for 'android/data'. A tree URI returned by the SAF picker is
// percent-encoded ('…/tree/primary%3AAndroid%2Fdata%2F…'), so the substring never
// matched, the function reported "no grant needed", and nothing was ever
// verified. It only appeared to work because the grant already existed from the
// pick — losing it (e.g. reinstalling the APK) turned into an opaque sync error
// instead of a fresh prompt.
//
// Note on coverage: `ensureSafPermission` itself returns true immediately on any
// non-Android platform, so testing it directly from the host would be green and
// meaningless. Extracting the policy into `safNeededFor` is what makes the rule
// actually testable.
void main() {
  group('SystemPathService.toPosix', () {
    test('leaves a plain POSIX path untouched', () {
      expect(SystemPathService.toPosix('/storage/emulated/0/RetroArch/saves'),
          '/storage/emulated/0/RetroArch/saves');
    });

    test('strips the shizuku scheme', () {
      expect(SystemPathService.toPosix('shizuku:///storage/emulated/0/PSP'),
          '/storage/emulated/0/PSP');
    });

    test('decodes a primary-volume SAF tree URI', () {
      expect(
        SystemPathService.toPosix(
            'content://com.android.externalstorage.documents/tree/primary%3AAndroid%2Fdata%2Fxyz.aethersx2.android%2Ffiles'),
        '/storage/emulated/0/Android/data/xyz.aethersx2.android/files',
      );
    });

    test('maps a non-primary volume to its /storage mount', () {
      expect(
        SystemPathService.toPosix(
            'content://com.android.externalstorage.documents/tree/1234-5678%3ARoms%2Fps2'),
        '/storage/1234-5678/Roms/ps2',
      );
    });

    test('returns a non-tree content URI unchanged so callers can detect it', () {
      const single =
          'content://com.android.externalstorage.documents/document/primary%3ARoms';
      expect(SystemPathService.toPosix(single), single);
    });
  });

  group('SystemPathService.safNeededFor', () {
    test('is false for an unrestricted POSIX path', () {
      expect(SystemPathService.safNeededFor('/storage/emulated/0/RetroArch/saves'),
          isFalse);
      expect(SystemPathService.safNeededFor('/storage/emulated/0/PSP/SAVEDATA'),
          isFalse);
    });

    test('is false for a shizuku path even inside Android/data', () {
      expect(
        SystemPathService.safNeededFor(
            'shizuku:///storage/emulated/0/Android/data/dev.eden.eden_emulator/files'),
        isFalse,
      );
    });

    test('is true for a POSIX path inside Android/data', () {
      expect(
        SystemPathService.safNeededFor(
            '/storage/emulated/0/Android/data/org.dolphinemu.dolphinemu/files'),
        isTrue,
      );
    });

    test('is case-insensitive', () {
      expect(
        SystemPathService.safNeededFor(
            '/storage/emulated/0/ANDROID/DATA/me.magnum.melonds/files'),
        isTrue,
      );
    });

    test('is true for a percent-encoded SAF tree URI inside Android/data', () {
      // The case that was silently broken before normalisation.
      expect(
        SystemPathService.safNeededFor(
            'content://com.android.externalstorage.documents/tree/primary%3AAndroid%2Fdata%2Fxyz.aethersx2.android%2Ffiles'),
        isTrue,
      );
    });

    test('is false for a SAF tree URI outside Android/data', () {
      expect(
        SystemPathService.safNeededFor(
            'content://com.android.externalstorage.documents/tree/primary%3ARoms%2Fps2'),
        isFalse,
      );
    });
  });
}
