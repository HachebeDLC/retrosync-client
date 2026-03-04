import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../sync/services/system_path_service.dart';
import '../../emulation/presentation/emulator_providers.dart';
import '../../emulation/domain/emulator_config.dart';

class LibrarySetupScreen extends ConsumerStatefulWidget {
  const LibrarySetupScreen({super.key});

  @override
  ConsumerState<LibrarySetupScreen> createState() => _LibrarySetupScreenState();
}

class _LibrarySetupScreenState extends ConsumerState<LibrarySetupScreen> {
  final _pathController = TextEditingController();
  bool _isScanning = false;
  List<String> _foundSystems = [];
  Map<String, String> _configuredPaths = {};

  @override
  void initState() {
    super.initState();
    _checkPermissions();
    _loadSavedPath();
    _loadConfiguredPaths();
  }

  Future<void> _checkPermissions() async {
    var status = await Permission.manageExternalStorage.status;
    if (!status.isGranted) {
      status = await Permission.manageExternalStorage.request();
    }
  }

  Future<void> _loadSavedPath() async {
    final savedPath = await ref.read(systemPathServiceProvider).getLibraryPath();
    if (savedPath != null && mounted) {
      setState(() {
        _pathController.text = savedPath;
      });
    } else {
      _pathController.text = '/storage/emulated/0/Roms';
    }
  }

  Future<void> _loadConfiguredPaths() async {
    final paths = await ref.read(systemPathServiceProvider).getAllSystemPaths();
    if (mounted) {
      setState(() {
        _configuredPaths = paths;
      });
    }
  }

  Future<void> _pickGlobalFolder() async {
    String? selectedDirectory = await ref.read(systemPathServiceProvider).openDirectoryPicker();
    if (selectedDirectory != null) {
      setState(() {
        _pathController.text = selectedDirectory;
      });
      await ref.read(systemPathServiceProvider).setLibraryPath(selectedDirectory);
    }
  }

  Future<void> _scan() async {
    setState(() => _isScanning = true);
    await ref.read(systemPathServiceProvider).setLibraryPath(_pathController.text);
    
    try {
      final path = _pathController.text;
      final found = await ref.read(systemPathServiceProvider).scanLibrary(path);
      setState(() => _foundSystems = found);
      await _loadConfiguredPaths();
      
      if (found.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No systems found in that folder.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  Future<void> _configureSystem(String systemId) async {
    final systems = await ref.read(systemsProvider.future);
    final system = systems.firstWhere((s) => s.system.id == systemId);
    final pathService = ref.read(systemPathServiceProvider);
    
    final currentEmulatorId = await pathService.getSystemEmulator(systemId);
    final currentPath = await pathService.getSystemPath(systemId);

    if (!mounted) return;

    final selectedEmulatorId = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Select Emulator for ${system.system.name}'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: system.emulators.length,
            itemBuilder: (context, index) {
              final emu = system.emulators[index];
              final isSelected = emu.uniqueId == currentEmulatorId;
              return ListTile(
                title: Text(emu.name, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                subtitle: Text(emu.uniqueId),
                selected: isSelected,
                trailing: isSelected ? const Icon(Icons.check, color: Colors.blue) : null,
                onTap: () => Navigator.pop(context, emu.uniqueId),
              );
            },
          ),
        ),
      ),
    );

    if (selectedEmulatorId == null) return;

    final emulator = system.emulators.firstWhere((e) => e.uniqueId == selectedEmulatorId);
    String initialPath = pathService.suggestSavePath(emulator, systemId);
    if (selectedEmulatorId == currentEmulatorId && currentPath != null) {
      initialPath = currentPath;
    }

    if (!mounted) return;

    final pathController = TextEditingController(text: initialPath);
    final confirmedPath = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Configure Save Path'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Emulator: ${emulator.name}', style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                const Text('Save Folder:'),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: pathController,
                        decoration: const InputDecoration(
                          hintText: '/storage/emulated/0/...',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.folder_open),
                      onPressed: () async {
                        String? initialUri;
                        if (pathController.text.startsWith('/storage/emulated/0/')) {
                          final relPath = pathController.text.substring(20).replaceAll('/', '%2F');
                          initialUri = 'content://com.android.externalstorage.documents/document/primary%3A$relPath';
                        }
                        String? picked = await ref.read(systemPathServiceProvider).openDirectoryPicker(initialUri: initialUri);
                        if (picked != null) {
                          setDialogState(() {
                            pathController.text = picked;
                          });
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(context, pathController.text), child: const Text('Save')),
          ],
        ),
      ),
    );

    if (confirmedPath != null && confirmedPath.isNotEmpty) {
      await pathService.setSystemEmulator(systemId, selectedEmulatorId);
      await pathService.setSystemPath(systemId, confirmedPath);
      await _loadConfiguredPaths();
      ref.invalidate(systemPathsProvider);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Library Setup'),
        actions: [
          if (_foundSystems.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  backgroundColor: Colors.green.withOpacity(0.8),
                  foregroundColor: Colors.white,
                ),
                onPressed: () => context.go('/dashboard'),
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('FINISH SETUP', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
        ],
      ),
      body: Row(
        children: [
          // LEFT PANEL: CONTROLS
          SizedBox(
            width: 320,
            child: Container(
              color: Colors.black26,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('1. SELECT ROMS ROOT',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, color: Colors.blue)),
                    const SizedBox(height: 8),
                    const Text('Base folder containing your game subfolders.',
                        style: TextStyle(fontSize: 13, color: Colors.grey)),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _pathController,
                      decoration: const InputDecoration(
                        labelText: 'Path',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: _pickGlobalFolder,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Browse Folders'),
                    ),
                    const SizedBox(height: 32),
                    const Text('2. AUTO-SCAN',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, color: Colors.blue)),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 54,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.withOpacity(0.2)),
                        onPressed: _isScanning ? null : _scan,
                        child: _isScanning
                            ? const CircularProgressIndicator()
                            : const Text('SCAN LIBRARY',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                    if (_foundSystems.isNotEmpty) ...[
                      const SizedBox(height: 32),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.withOpacity(0.2),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        onPressed: () => context.go('/dashboard'),
                        icon: const Icon(Icons.check_circle_outline, color: Colors.green),
                        label: const Text('FINISH SETUP', 
                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          
          // RIGHT PANEL: DETECTED SYSTEMS
          Expanded(
            child: _foundSystems.isEmpty 
              ? const Center(child: Text('No systems detected yet.\nSelect your ROMs root and click "Scan".', textAlign: TextAlign.center))
              : FutureBuilder<List<EmulatorConfig>>(
                  future: ref.watch(systemsProvider.future),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                    final systems = snapshot.data!.where((s) => _foundSystems.contains(s.system.id)).toList();
                    
                    return ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: systems.length,
                      itemBuilder: (context, index) {
                        final sys = systems[index];
                        final isConfigured = _configuredPaths.containsKey(sys.system.id);
                        
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: Icon(
                              Icons.gamepad, 
                              color: isConfigured ? Colors.blue : Colors.orange
                            ),
                            title: Text(sys.system.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text(isConfigured ? 'Configured' : 'Needs Setup'),
                            trailing: isConfigured 
                              ? const Icon(Icons.check_circle, color: Colors.green)
                              : const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                            onTap: () => _configureSystem(sys.system.id),
                          ),
                        );
                      },
                    );
                  }
                ),
          ),
        ],
      ),
    );
  }
}
