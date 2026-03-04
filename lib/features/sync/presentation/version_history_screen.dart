import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/sync_repository.dart';

class VersionHistoryScreen extends ConsumerStatefulWidget {
  final String remotePath;
  final String localBasePath;
  final String relPath;

  const VersionHistoryScreen({
    super.key,
    required this.remotePath,
    required this.localBasePath,
    required this.relPath,
  });

  @override
  ConsumerState<VersionHistoryScreen> createState() => _VersionHistoryScreenState();
}

class _VersionHistoryScreenState extends ConsumerState<VersionHistoryScreen> {
  List<Map<String, dynamic>> _versions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadVersions();
  }

  Future<void> _loadVersions() async {
    setState(() => _isLoading = true);
    try {
      final versions = await ref.read(syncRepositoryProvider).getFileVersions(widget.remotePath);
      setState(() {
        _versions = versions;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _restore(int version) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore Version'),
        content: Text('Are you sure you want to restore Version $version? This will overwrite your current local save.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Restore')),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isLoading = true);
      try {
        await ref.read(syncRepositoryProvider).restoreVersion(
          widget.remotePath, 
          version, 
          widget.localBasePath, 
          widget.relPath
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Restored successfully!')));
          Navigator.pop(context);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Restore failed: $e')));
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Version History')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _versions.isEmpty
              ? const Center(child: Text('No previous versions found on server.'))
              : ListView.builder(
                  itemCount: _versions.length,
                  itemBuilder: (context, index) {
                    final v = _versions[index];
                    final versionNum = v['version'];
                    final date = DateTime.fromMillisecondsSinceEpoch(v['updated_at']);
                    final size = (v['size'] / 1024).toStringAsFixed(1);

                    return ListTile(
                      leading: CircleAvatar(child: Text('v$versionNum')),
                      title: Text('Backup from ${date.toLocal()}'),
                      subtitle: Text('$size KB'),
                      trailing: ElevatedButton(
                        onPressed: () => _restore(versionNum),
                        child: const Text('Restore'),
                      ),
                    );
                  },
                ),
    );
  }
}
