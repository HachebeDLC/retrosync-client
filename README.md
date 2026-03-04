# NeoSync Mobile App

This is a Flutter project for a standalone sync client for the NeoSync server.

## Features
- Connects to your self-hosted NeoSync server.
- Scans a local directory (e.g., your RetroArch saves).
- Syncs files (Upload/Download) based on modifications.
- Supports background sync (optional, requires work manager).

## Setup
1. Install Flutter SDK.
2. Run `flutter pub get`.
3. Run `flutter run`.

## Build APK
```bash
flutter build apk --release
```

## Configuration
Edit `lib/main.dart` to set your server URL if not using the UI.
