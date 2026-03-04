import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/emulator_config.dart';

final emulatorRepositoryProvider = Provider<EmulatorRepository>((ref) {
  return EmulatorRepository();
});

class EmulatorRepository {
  Future<List<EmulatorConfig>> loadSystems() async {
    try {
      print('Loading systems from AssetManifest...');
      final AssetManifest manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final allAssets = manifest.listAssets();
      print('Total assets in manifest: ${allAssets.length}');
      
      final systemFiles = allAssets
          .where((String key) => key.contains('assets/systems/') && key.endsWith('.json'))
          .toList();

      print('Found ${systemFiles.length} system files in manifest');
      if (systemFiles.isEmpty) {
        print('Sample asset keys: ${allAssets.take(10).join(', ')}');
      }

      List<EmulatorConfig> systems = [];
      for (final file in systemFiles) {
        try {
          final String jsonString = await rootBundle.loadString(file);
          final Map<String, dynamic> jsonMap = json.decode(jsonString);
          systems.add(EmulatorConfig.fromJson(jsonMap));
        } catch (e) {
          print('Error loading system file $file: $e');
        }
      }
      return systems;
    } catch (e) {
      print('Error loading AssetManifest via new API: $e');
      // Fallback for older Flutter versions
      try {
        print('Trying fallback manifest loading...');
        final manifestContent = await rootBundle.loadString('AssetManifest.json');
        final Map<String, dynamic> manifest = json.decode(manifestContent);
        final systemFiles = manifest.keys
            .where((String key) => key.contains('assets/systems/') && key.endsWith('.json'))
            .toList();
        
        print('Found ${systemFiles.length} system files in fallback manifest');

        List<EmulatorConfig> systems = [];
        for (final file in systemFiles) {
          final String jsonString = await rootBundle.loadString(file);
          final Map<String, dynamic> jsonMap = json.decode(jsonString);
          systems.add(EmulatorConfig.fromJson(jsonMap));
        }
        return systems;
      } catch (e2) {
        print('Fallback Error loading AssetManifest.json: $e2');
        return [];
      }
    }
  }
}
