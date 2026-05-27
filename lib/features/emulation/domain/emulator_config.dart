class EmulatorConfig {
  final SystemInfo system;
  final List<EmulatorInfo> emulators;

  EmulatorConfig({required this.system, required this.emulators});

  EmulatorConfig copyWith({List<EmulatorInfo>? emulators}) {
    return EmulatorConfig(
      system: system,
      emulators: emulators ?? this.emulators,
    );
  }

  factory EmulatorConfig.fromJson(Map<String, dynamic> json) {
    return EmulatorConfig(
      system: SystemInfo.fromJson(json['system']),
      emulators: (json['emulators'] as List)
          .map((e) => EmulatorInfo.fromJson(e))
          .toList(),
    );
  }
}

class SystemInfo {
  final String id;
  final String name;
  final List<String> folders;
  // ROM extensions — used by the emulator picker for "is this file a game".
  final List<String> extensions;
  final List<String> ignoredFolders;
  // SAVE extensions — when populated, the file scanner only syncs files with
  // these extensions for this system. When empty, the scanner falls back to
  // its global hardcoded set.
  final List<String> saveExtensions;

  SystemInfo({
    required this.id,
    required this.name,
    required this.folders,
    required this.extensions,
    required this.ignoredFolders,
    this.saveExtensions = const [],
  });

  factory SystemInfo.fromJson(Map<String, dynamic> json) {
    return SystemInfo(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      folders: List<String>.from(json['folders'] ?? []),
      extensions: List<String>.from(json['extensions'] ?? []),
      ignoredFolders: List<String>.from(json['ignored_folders'] ?? []),
      saveExtensions: List<String>.from(json['save_extensions'] ?? []),
    );
  }
}

class EmulatorInfo {
  final String name;
  final String uniqueId;
  final bool defaultEmulator;
  final bool isInstalled;

  EmulatorInfo({
    required this.name,
    required this.uniqueId,
    required this.defaultEmulator,
    this.isInstalled = false,
  });

  EmulatorInfo copyWith({bool? isInstalled}) {
    return EmulatorInfo(
      name: name,
      uniqueId: uniqueId,
      defaultEmulator: defaultEmulator,
      isInstalled: isInstalled ?? this.isInstalled,
    );
  }

  factory EmulatorInfo.fromJson(Map<String, dynamic> json) {
    return EmulatorInfo(
      name: json['name'] ?? '',
      uniqueId: json['unique_id'] ?? '',
      defaultEmulator: json['default'] ?? false,
    );
  }
}
