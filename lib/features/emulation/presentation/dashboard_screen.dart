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
          return 'SD Card/${parts.last.split('/document/').last}';
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
        title: const Text('VaultSync Dashboard'),
        actions: [
          IconButton(
            tooltip: 'Scan Library',
            icon: const Icon(Icons.search),
            onPressed: () => context.push('/library-setup'),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: pathsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
        data: (paths) {
          print('🎨 RENDER: Dashboard building with ${paths.length} systems');
          
          if (paths.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.folder_open, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text('No systems configured yet.'),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.search),
                    label: const Text('Scan Library'),
                    onPressed: () => context.push('/library-setup'),
                  ),
                ],
              ),
            );
          }

          return LayoutBuilder(builder: (context, constraints) {
            final isWide = constraints.maxWidth > 600;
            
            final systemsListView = ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: paths.length,
              itemBuilder: (context, index) {
                final entry = paths.entries.elementAt(index);
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.blue.withOpacity(0.1),
                      child: Icon(_getSystemIcon(entry.key), color: Colors.blue),
                    ),
                    title: Text(entry.key.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(_formatSafPath(entry.value), maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: const Icon(Icons.check_circle, color: Colors.green, size: 20),
                  ),
                );
              },
            );

            final statusCard = Card(
              elevation: 4,
              margin: const EdgeInsets.all(16),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      syncState.isSyncing ? Icons.sync : Icons.cloud_done,
                      size: 64,
                      color: syncState.isSyncing ? Colors.blue : Colors.green,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      syncState.isSyncing ? 'Syncing...' : 'System Ready',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(syncState.status.isEmpty ? 'Waiting for changes' : syncState.status),
                    const SizedBox(height: 24),
                    if (syncState.isSyncing)
                      LinearProgressIndicator(value: syncState.progress)
                    else
                      ElevatedButton.icon(
                        icon: const Icon(Icons.sync),
                        label: const Text('Sync All Systems'),
                        style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 54)),
                        onPressed: () => ref.read(syncProvider.notifier).sync(),
                      ),
                  ],
                ),
              ),
            );

            if (isWide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 4, child: SingleChildScrollView(child: statusCard)),
                  const VerticalDivider(width: 1),
                  Expanded(flex: 6, child: systemsListView),
                ],
              );
            } else {
              return Column(
                children: [
                  statusCard,
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.0),
                    child: Divider(),
                  ),
                  Expanded(child: systemsListView),
                ],
              );
            }
          });
        },
      ),
    );
  }
}
