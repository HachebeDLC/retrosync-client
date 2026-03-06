import 'package:flutter/material.dart';
import '../domain/emulator_config.dart';

class EmulatorListScreen extends StatelessWidget {
  final EmulatorConfig system;

  const EmulatorListScreen({super.key, required this.system});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${system.system.name} Emulators'),
      ),
      body: ListView.builder(
        itemCount: system.emulators.length,
        itemBuilder: (context, index) {
          final emulator = system.emulators[index];
          return ListTile(
            title: Text(emulator.name),
            subtitle: Text(emulator.uniqueId),
          );
        },
      ),
    );
  }
}
