class EmulatorConfig {
  final SystemInfo system;
  final List<EmulatorInfo> emulators;

  EmulatorConfig({required this.system, required this.emulators});

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
  final SystemDetails details;
  final List<String> folders;
  final List<String> extensions;

  SystemInfo({
    required this.id,
    required this.name,
    required this.details,
    required this.folders,
    required this.extensions,
  });

  factory SystemInfo.fromJson(Map<String, dynamic> json) {
    return SystemInfo(
      id: json['id'],
      name: json['name'],
      details: SystemDetails.fromJson(json['details']),
      folders: List<String>.from(json['folders'] ?? []),
      extensions: List<String>.from(json['extensions'] ?? []),
    );
  }
}

class SystemDetails {
  final String manufacturer;
  final String releaseDate;
  final String description;

  SystemDetails({
    required this.manufacturer,
    required this.releaseDate,
    required this.description,
  });

  factory SystemDetails.fromJson(Map<String, dynamic> json) {
    return SystemDetails(
      manufacturer: json['manufacturer'] ?? '',
      releaseDate: json['release_date'] ?? '',
      description: json['description'] ?? '',
    );
  }
}

class EmulatorInfo {
  final String name;
  final String uniqueId;
  final String description;
  final bool isRetroAchievementsCompatible;
  final bool defaultEmulator;
  final Map<String, dynamic> platforms;

  EmulatorInfo({
    required this.name,
    required this.uniqueId,
    required this.description,
    required this.isRetroAchievementsCompatible,
    required this.defaultEmulator,
    required this.platforms,
  });

  factory EmulatorInfo.fromJson(Map<String, dynamic> json) {
    return EmulatorInfo(
      name: json['name'],
      uniqueId: json['unique_id'] ?? '',
      description: json['description'] ?? '',
      isRetroAchievementsCompatible: json['is_retroachievements_compatible'] ?? false,
      defaultEmulator: json['default'] ?? false,
      platforms: json['platforms'] ?? {},
    );
  }

  String? get packageName {
    final android = platforms['android'];
    if (android == null) return null;
    final args = android['launch_arguments'] as String?;
    if (args == null) return null;
    
    // Pattern: -n package/activity or -n package
    final match = RegExp(r'-n ([^/\s]+)').firstMatch(args);
    return match?.group(1);
  }
}