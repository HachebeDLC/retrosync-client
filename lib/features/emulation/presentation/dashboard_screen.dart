import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../sync/domain/sync_provider.dart';
import '../../sync/services/system_path_service.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  String _formatSafPath(String path) {
    if (path.startsWith('content://')) {
      try {
        final decoded = Uri.decodeComponent(path);
        if (decoded.contains('primary:')) {
          return '/storage/emulated/0/${decoded.split('primary:').last}';
        } else if (decoded.contains(':')) {
          final parts = decoded.split(':');
          if (parts.length > 2) {
             return 'SD Card/${parts.last.split('/document/').last}';
          }
          return 'SD Card/${parts[1].split('/document/').last}';
        }
        return decoded.split('/').last;
      } catch (_) {}
    }
    return path;
  }

  IconData _getSystemIcon(String systemId) {
    final id = systemId.toLowerCase();
    if (id.contains('gba') || id.contains('gbc') || id.contains('gb')) return Icons.gamepad;
    if (id.contains('ps1') || id.contains('ps2') || id.contains('psx') || id.contains('psp')) return Icons.sports_esports;
    if (id.contains('switch') || id.contains('ns')) return Icons.switch_left;
    if (id.contains('ds') || id.contains('3ds')) return Icons.developer_board;
    if (id.contains('n64') || id.contains('gc') || id.contains('wii')) return Icons.videogame_asset;
    if (id.contains('retroarch')) return Icons.settings_input_component;
    return Icons.folder;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncState = ref.watch(syncProvider);
    final pathsAsync = ref.watch(systemPathsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('NeoSync'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 600;

          final statusSection = Card(
            elevation: 4,
            margin: const EdgeInsets.only(bottom: 24),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    syncState.isSyncing ? Icons.sync : Icons.cloud_done,
                    size: 48,
                    color: syncState.isSyncing ? Colors.blue : Colors.green,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    syncState.isSyncing ? 'Syncing...' : 'Up to Date',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    syncState.status.isEmpty ? 'Ready to sync' : syncState.status,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                                      if (syncState.isSyncing)
                                        LinearProgressIndicator(value: syncState.progress)
                                      else ...[
                                        ElevatedButton.icon(
                                          icon: const Icon(Icons.sync),
                                          label: const Text('Sync Now'),
                                          style: ElevatedButton.styleFrom(
                                            minimumSize: const Size(200, 50),
                                          ),
                                          onPressed: () {
                                            ref.read(syncProvider.notifier).sync();
                                          },
                                        ),
                                        if (syncState.conflicts.isNotEmpty) ...[
                                          const SizedBox(height: 12),
                                          OutlinedButton.icon(
                                            icon: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                                            label: Text('Resolve ${syncState.conflicts.length} Conflicts'),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: Colors.orange,
                                              side: const BorderSide(color: Colors.orange),
                                            ),
                                            onPressed: () => context.push('/conflicts'),
                                          ),
                                        ],
                                      ],                ],
              ),
            ),
          );

          final systemsList = pathsAsync.when(
            data: (paths) {
              if (paths.isEmpty) {
                return Center(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('No systems configured.'),
                        const SizedBox(height: 8),
                        ElevatedButton(
                          onPressed: () => context.push('/library-setup'),
                          child: const Text('Setup Library'),
                        ),
                      ],
                    ),
                  ),
                );
              }
              return ListView(
                shrinkWrap: true,
                physics: isWide ? const NeverScrollableScrollPhysics() : null,
                children: paths.entries.map((e) {
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(child: Icon(_getSystemIcon(e.key))),
                      title: Text(e.key.toUpperCase()),
                      subtitle: Text(_formatSafPath(e.value), maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: const Icon(Icons.check_circle, color: Colors.green),
                    ),
                  );
                }).toList(),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, s) => Center(child: Text('Error: $e')),
          );

          if (isWide) {
            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: SingleChildScrollView(child: statusSection),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Configured Systems',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            TextButton.icon(
                              icon: const Icon(Icons.edit),
                              label: const Text('Manage'),
                              onPressed: () => context.push('/library-setup'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Expanded(child: SingleChildScrollView(child: systemsList)),
                      ],
                    ),
                  ),
                ],
              ),
            );
          } else {
            // Portrait Layout
            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  statusSection,
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Configured Systems',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.edit),
                        label: const Text('Manage'),
                        onPressed: () => context.push('/library-setup'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(child: systemsList),
                ],
              ),
            );
          }
        },
      ),
    );
  }
}
