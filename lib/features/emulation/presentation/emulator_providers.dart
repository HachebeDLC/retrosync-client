import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/emulator_repository.dart';
import '../domain/emulator_config.dart';

final systemsProvider = FutureProvider<List<EmulatorConfig>>((ref) async {
  final repository = ref.watch(emulatorRepositoryProvider);
  return repository.loadSystems();
});
