import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import '../../../core/services/api_client_provider.dart';

class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final _urlController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _urlController.text = '';
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  /// Cleans up a hand-typed server URL: adds a scheme when missing, drops a
  /// trailing slash, and rejects anything without a host.
  ///
  /// Returns null when [raw] cannot be a server URL.
  static String? normalizeUrl(String raw) {
    var url = raw.trim();
    if (url.isEmpty) return null;
    if (!url.contains('://')) url = 'https://$url';
    while (url.length > 1 && url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    return url;
  }

  /// Hits the server's `/` health check. Returns null on success, or a short
  /// human-readable reason on failure.
  Future<String?> _probe(String url) async {
    try {
      final response = await http
          .get(Uri.parse('$url/'))
          .timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) {
        return 'The server answered with HTTP ${response.statusCode}.';
      }
      final body = json.decode(response.body);
      if (body is Map && body['status'] == 'online') return null;
      return 'That address answered, but it does not look like a VaultSync server.';
    } catch (e) {
      developer.log('SETUP: Health check failed for $url',
          name: 'VaultSync', level: 900, error: e);
      return 'Could not reach the server. Check the address, the port and that '
          'you are on the same network.';
    }
  }

  /// Lets the user store an unreachable URL anyway, so a server that is merely
  /// switched off cannot lock them out of setup.
  Future<bool> _confirmUnreachable(String reason) async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Can't reach that server"),
        content: Text('$reason\n\nYou can save it anyway and try again later.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('EDIT ADDRESS'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('SAVE ANYWAY'),
          ),
        ],
      ),
    );
    return proceed ?? false;
  }

  Future<void> _saveUrl() async {
    setState(() => _isLoading = true);
    try {
      final url = normalizeUrl(_urlController.text);
      if (url == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a valid URL')),
        );
        return;
      }

      final failure = await _probe(url);
      if (!mounted) return;
      if (failure != null && !await _confirmUnreachable(failure)) {
        if (mounted) _urlController.text = url;
        return;
      }

      await ref.read(apiClientProvider).setBaseUrl(url);

      if (mounted) {
        // Proceed to Login/Register
        context.go('/auth');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving URL: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Server Connection')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 450),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.dns, size: 80, color: Colors.blue),
                const SizedBox(height: 32),
                Text(
                  'Connect to VaultSync Server',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Enter the URL of your self-hosted VaultSync instance.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 48),
                TextField(
                  controller: _urlController,
                  decoration: const InputDecoration(
                    labelText: 'Server URL',
                    hintText: 'https://vaultsync.example.com',
                    helperText: 'For a LAN server include the port, e.g. '
                        'http://192.168.1.50:8080',
                    helperMaxLines: 2,
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.link),
                  ),
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  onSubmitted: _isLoading ? null : (_) => _saveUrl(),
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: _isLoading ? null : _saveUrl,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('CONNECT TO SERVER', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
