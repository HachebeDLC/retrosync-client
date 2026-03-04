import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/api_client_provider.dart';
import '../../auth/domain/auth_provider.dart';
import '../../sync/services/system_path_service.dart';
import '../../sync/services/sync_watcher_service.dart';

class BootScreen extends ConsumerStatefulWidget {
  const BootScreen({super.key});

  @override
  ConsumerState<BootScreen> createState() => _BootScreenState();
}

class _BootScreenState extends ConsumerState<BootScreen> {
  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final isConfigured = await ref.read(apiClientProvider).isConfigured();
    
    if (!mounted) return;

    if (!isConfigured) {
      context.go('/setup');
      return;
    }

    await ref.read(authProvider.notifier).init();
    await Future.delayed(const Duration(seconds: 1));

    if (!mounted) return;

    if (ref.read(authProvider.notifier).isAuthenticated) {
      final paths = await ref.read(systemPathServiceProvider).getAllSystemPaths();
      if (!mounted) return;
      
      if (paths.isEmpty) {
        context.go('/library-setup');
      } else {
        // Start live file watcher
        // ref.read(syncWatcherServiceProvider).startWatching(); // Re-enable if service exists
        context.go('/dashboard');
      }
    } else {
      context.go('/auth');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text(
              'Initializing NeoSync...',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ],
        ),
      ),
    );
  }
}
