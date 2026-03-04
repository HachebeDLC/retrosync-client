import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:workmanager/workmanager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../core/services/api_client_provider.dart';
import '../../sync/services/system_path_service.dart';
import '../../auth/domain/auth_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _urlController = TextEditingController();
  bool _autoSync = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final url = await ref.read(apiClientProvider).getBaseUrl();
    _urlController.text = url ?? '';

    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _autoSync = prefs.getBool('auto_sync') ?? false;
    });
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _toggleAutoSync(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_sync', value);
    setState(() => _autoSync = value);

    if (value) {
      await Workmanager().registerPeriodicTask(
        "syncTask",
        "syncTaskName",
        frequency: const Duration(minutes: 15),
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: true,
        ),
      );
    } else {
      await Workmanager().cancelAll();
    }
  }

  Future<void> _logout() async {
    // await ref.read(authProvider.notifier).logout(); // Assuming logout exists or just clear token
    await ref.read(apiClientProvider).clearToken();
    if (mounted) context.go('/auth');
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          ListTile(
            title: const Text('Dark Mode'),
            trailing: Switch(
              value: themeMode == ThemeMode.dark,
              onChanged: (value) {
                ref.read(themeProvider.notifier).toggleTheme();
              },
            ),
          ),
          ListTile(
            title: const Text('Auto Sync (Background)'),
            subtitle: const Text('Every 15 mins when idle'),
            trailing: Switch(
              value: _autoSync,
              onChanged: _toggleAutoSync,
            ),
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8.0),
            child:
                Text('Network', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          TextField(
            controller: _urlController,
            decoration: const InputDecoration(
              labelText: 'Server URL',
              hintText: 'http://10.0.2.2:8000',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: () async {
              await ref.read(apiClientProvider).setBaseUrl(_urlController.text);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Server URL saved')),
                );
              }
            },
            child: const Text('Save Server URL'),
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8.0),
            child: Text('Danger Zone',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.withOpacity(0.2)),
            onPressed: _logout,
            child: const Text('Logout / Clear Data', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
