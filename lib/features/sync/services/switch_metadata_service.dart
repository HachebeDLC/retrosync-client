class SwitchMetadataService {
  /// Extracts the Title ID from a Switch ROM (NSP/XCI).
  /// For now, it attempts to find it in the filename pattern [0100XXXXXXXXXXXX].
  /// Future implementation will use prod.keys to parse headers.
  String? extractTitleId(String filePath) {
    final filename = filePath.split('/').last;
    final match = RegExp(r'\[(0100[0-9A-Fa-f]{12})\]').firstMatch(filename);
    
    if (match != null) {
      return match.group(1)?.toUpperCase();
    }
    
    // Fallback: If no Title ID in filename, we could eventually 
    // read the first few MBs of the file and parse the CNMT.
    return null;
  }

  /// Constructs the precise save path for a Switch game on Android.
  String? getSavePathForTitle(String baseEmulatorPath, String titleId) {
    // Standard Yuzu/Eden path structure for saves:
    // <base>/nand/user/save/0000000000000000/<TITLE_ID>/
    
    final path = '$baseEmulatorPath/nand/user/save/0000000000000000/$titleId';
    return path;
  }
}
