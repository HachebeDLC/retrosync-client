# Flutter App Refactoring Plan (VaultSync)

This plan outlines the steps to refactor the `neosync_app/lib/main.dart` file into a more organized and maintainable Flutter project structure.

## Current State
All application logic (models, providers, screens, services) is currently contained within `neosync_app/lib/main.dart`.

## Goal
To organize the codebase into a standard Flutter project structure, separating concerns into dedicated files and directories for better readability, maintainability, and scalability.

## Proposed New Structure

```
neosync_app/
├── lib/
│   ├── main.dart             // Main entry point, sets up MultiProvider and runs NeoSyncApp
│   ├── models/
│   │   └── emulator_config.dart // Defines the EmulatorConfig class
│   ├── providers/
│   │   ├── auth_provider.dart   // Manages authentication state, JWT tokens, secure storage, server URL
│   │   └── theme_provider.dart  // Manages theme mode (light/dark/system) persistence
│   ├── screens/
│   │   ├── boot_screen.dart     // Handles initial app load, checks auth status and server URL, redirects
│   │   ├── setup_screen.dart    // UI for initial server URL configuration and health check
│   │   ├── auth_screen.dart     // UI for user login and registration
│   │   ├── dashboard_screen.dart// Main UI for displaying emulator list and triggering sync
│   │   └── settings_screen.dart // UI for app settings (theme, server URL change, logout)
│   └── services/
│       └── sync_manager.dart    // Contains all core sync logic (file scanning, upload, download, conflict resolution, encryption/decryption)
└── pubspec.yaml
└── pubspec.lock
└── README.md
└── ... (other Flutter project files like android/, ios/, etc.)
```

## Refactoring Tasks

1.  **Create Directories:** Set up the `models/`, `providers/`, `screens/`, and `services/` directories inside `lib/`.

2.  **Extract `EmulatorConfig` Model:**
    *   Create `lib/models/emulator_config.dart`.
    *   Move the `EmulatorConfig` class definition into this new file.
    *   Update `main.dart` and other affected files to import `emulator_config.dart`.

3.  **Extract `ThemeProvider`:**
    *   Create `lib/providers/theme_provider.dart`.
    *   Move the `ThemeProvider` class into this new file.
    *   Update `main.dart` and other affected files to import `theme_provider.dart`.

4.  **Extract `AuthProvider`:**
    *   Create `lib/providers/auth_provider.dart`.
    *   Move the `AuthProvider` class into this new file.
    *   Update `main.dart` and other affected files to import `auth_provider.dart`.

5.  **Extract `SyncManager` Service:**
    *   Create `lib/services/sync_manager.dart`.
    *   Move the `SyncManager` class and its helper functions (`_getEncrypter`) into this new file.
    *   Update `main.dart` and other affected files to import `sync_manager.dart`.

6.  **Extract Screens:**
    *   Create `lib/screens/boot_screen.dart` and move `BootScreen` into it.
    *   Create `lib/screens/setup_screen.dart` and move `SetupScreen` into it.
    *   Create `lib/screens/auth_screen.dart` and move `AuthScreen` into it.
    *   Create `lib/screens/dashboard_screen.dart` and move `DashboardScreen` into it.
    *   Create `lib/screens/settings_screen.dart` and move `SettingsScreen` into it.
    *   Update `main.dart` and other affected files to import these new screen files.

7.  **Update `main.dart`:**
    *   `main.dart` will be simplified to contain only `void main()` and `NeoSyncApp`.
    *   It will import all necessary providers and screens from their new locations.

8.  **Verify Imports:** Ensure all `import` statements across the refactored files are correct and point to the new locations.

9.  **Test:** After refactoring, rebuild the app and test all functionalities to ensure nothing was broken during the migration.
