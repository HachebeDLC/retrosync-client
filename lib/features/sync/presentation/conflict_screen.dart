import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/sync_provider.dart';

class ConflictScreen extends ConsumerWidget {
  const ConflictScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncState = ref.watch(syncProvider);
    final conflicts = syncState.conflicts;

    return Scaffold(
      appBar: AppBar(title: const Text('Sync Conflicts')),
      body: conflicts.isEmpty
          ? const Center(child: Text('No active conflicts.'))
          : ListView.builder(
              itemCount: conflicts.length,
              itemBuilder: (context, index) {
                final conflict = conflicts[index];
                final String path = conflict['path'] ?? 'Unknown path';
                final String deviceName = conflict['device_name'] ?? 'Unknown Device';
                
                // Parse timestamp from filename: ...sync-conflict-YYYYMMDD-HHMMSS-DeviceSlug.ext
                String displayDate = 'Unknown date';
                if (path.contains('.sync-conflict-')) {
                   try {
                     final parts = path.split('.sync-conflict-')[1].split('-');
                     final datePart = parts[0];
                     // 20260225
                     final year = datePart.substring(0, 4);
                     final month = datePart.substring(4, 6);
                     final day = datePart.substring(6, 8);
                     
                     String timeDisplay = 'Unknown time';
                     if (parts.length > 1) {
                        final rawTime = parts[1];
                        if (rawTime.length >= 6) {
                           timeDisplay = "${rawTime.substring(0,2)}:${rawTime.substring(2,4)}:${rawTime.substring(4,6)}";
                        }
                     }
                     
                     displayDate = '$year-$month-$day $timeDisplay';
                   } catch (_) {}
                }

                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                path.split('/').last.split('.sync-conflict-').first,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.devices, size: 14, color: Colors.blue),
                            const SizedBox(width: 4),
                            Text('Device: $deviceName', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.access_time, size: 14, color: Colors.grey),
                            const SizedBox(width: 4),
                            Text('Conflict created on: $displayDate', style: const TextStyle(fontSize: 13)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text('Cloud Path: $path', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        const Divider(height: 24),
                        const Text(
                          'A discrepancy was found. Which version do you want to keep as the primary save?',
                          style: TextStyle(fontSize: 14),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () => _resolve(context, ref, conflict, true),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue, 
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                                child: const Text('Keep Local'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () => _resolve(context, ref, conflict, false),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green, 
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                                child: const Text('Keep Cloud'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Future<void> _resolve(BuildContext context, WidgetRef ref, Map<String, dynamic> conflict, bool keepLocal) async {
    final fileName = (conflict['path'] as String).split('/').last.split('.sync-conflict-').first;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Resolving $fileName...'), duration: const Duration(seconds: 1)),
    );
    
    try {
      await ref.read(syncProvider.notifier).resolveConflict(conflict, keepLocal);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Resolved: $fileName kept ${keepLocal ? 'Local' : 'Cloud'} version.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error resolving conflict: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}
