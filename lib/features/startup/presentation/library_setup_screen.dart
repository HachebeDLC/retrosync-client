import 'dart:developer' as developer;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../sync/services/system_path_service.dart';
import '../../sync/services/shizuku_service.dart';
import '../../emulation/presentation/emulator_providers.dart';
import '../../emulation/domain/emulator_config.dart';
import '../../../core/utils/platform_utils.dart';

class LibrarySetupScreen extends ConsumerStatefulWidget {
  const LibrarySetupScreen({super.key});

  @override
  ConsumerState<LibrarySetupScreen> createState() => _LibrarySetupScreenState();
}

class _LibrarySetupScreenState extends ConsumerState<LibrarySetupScreen> {
  final _pathController = TextEditingController();
  bool _isScanning = false;
  List<Map<String, String>> _foundSystems = [];
  Map<String, String> _configuredPaths = {};

  /// systemId -> whether the configured save folder is actually reachable.
  /// Auto-suggested paths are guesses (see [SystemPathService.pathExists]), so a
  /// system can be "configured" and still sync nothing.
  Map<String, bool> _pathReachable = {};

  /// Systems found on disk but skipped because no emulator for them is
  /// installed. Auto-assign cannot run for these, and `systemsProvider` hides
  /// them on Android, so without this they vanish with no explanation.
  List<String> _skippedNoEmulator = [];

  bool _shizukuEnabled = false;
  ShizukuStatus? _shizukuStatus;
  bool _grantingSaf = false;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
    _loadSavedPath();
    _loadConfiguredPaths();
    _checkShizuku();
  }

  Future<void> _checkPermissions() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    
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
    } else if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      _pathController.text = '';
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
    await _verifyConfiguredPaths(paths);
  }

  /// Checks whether each configured save folder can actually be read, and stores
  /// the result in [_pathReachable].
  ///
  /// Resolves through `getEffectivePath` rather than the stored value so the
  /// check runs against the exact path the sync will use — POSIX, a SAF tree
  /// URI, or `shizuku://` depending on the current transport. That also means a
  /// dead Shizuku binder shows up here as unreachable, instead of later as a
  /// sync that silently skips the system.
  Future<void> _verifyConfiguredPaths(Map<String, String> paths) async {
    final service = ref.read(systemPathServiceProvider);
    final results = <String, bool>{};
    for (final systemId in paths.keys) {
      try {
        final effective = await service.getEffectivePath(systemId);
        results[systemId] = await service.pathExists(effective);
      } catch (e) {
        developer.log('SETUP: Could not verify path for $systemId',
            name: 'VaultSync', level: 900, error: e);
        results[systemId] = false;
      }
    }
    if (mounted) setState(() => _pathReachable = results);
  }

  Future<void> _checkShizuku() async {
    if (!Platform.isAndroid) return;
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('use_shizuku') ?? false;
    final status = await ref.read(shizukuServiceProvider).getStatus();
    if (mounted) {
      setState(() {
        _shizukuEnabled = enabled;
        _shizukuStatus = status;
      });
    }
  }

  Future<void> _setShizukuEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('use_shizuku', enabled);
    if (!mounted) return;
    setState(() => _shizukuEnabled = enabled);
    ref.invalidate(systemPathsProvider);
    await _checkShizuku();
    // The transport changed, so every path has to be re-checked.
    await _loadConfiguredPaths();
  }

  Future<void> _fixShizuku() async {
    final status = _shizukuStatus;
    if (status == null) return;

    if (!status.isRunning) {
      await ref.read(shizukuServiceProvider).openApp();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Opening Shizuku — start the service, then come back.')),
      );
      return;
    }

    final success = await ref.read(shizukuServiceProvider).requestPermission();
    if (!mounted) return;
    if (success) {
      await _checkShizuku();
      await _loadConfiguredPaths();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Shizuku authorized.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Shizuku denied the request.')),
      );
    }
  }

  /// Configured paths that still need an explicit SAF grant.
  ///
  /// Always empty while Shizuku is enabled, because `getEffectivePath` routes
  /// everything through the binder and `ensureSafPermission` short-circuits.
  List<String> get _pathsNeedingSaf {
    if (!Platform.isAndroid || _shizukuEnabled) return const [];
    return _configuredPaths.entries
        .where((e) => SystemPathService.safNeededFor(e.value))
        .map((e) => e.key)
        .toList();
  }

  /// Walks the restricted paths and asks for each grant up front, so the user
  /// isn't ambushed by a picker in the middle of their first sync — where a
  /// cancel used to abort every remaining system.
  Future<void> _grantSafPermissions() async {
    final pending = _pathsNeedingSaf;
    if (pending.isEmpty) return;

    setState(() => _grantingSaf = true);
    final service = ref.read(systemPathServiceProvider);
    final declined = <String>[];
    try {
      for (final systemId in pending) {
        final path = _configuredPaths[systemId];
        if (path == null) continue;
        final granted = await service.ensureSafPermission(path);
        if (!granted) declined.add(systemId);
        if (!mounted) return;
      }
    } finally {
      if (mounted) setState(() => _grantingSaf = false);
    }

    await _loadConfiguredPaths();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(declined.isEmpty
            ? 'All folder permissions granted.'
            : 'Still missing permission for: ${declined.join(', ')}'),
      ),
    );
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
    final service = ref.read(systemPathServiceProvider);
    await service.setLibraryPath(_pathController.text);
    
    try {
      final path = _pathController.text;
      final found = await service.scanLibrary(path);
      
      final skipped = <String>[];

      // Auto-save the detected paths and configure default emulators
      if (found.isNotEmpty) {
        final systems = await ref.read(systemsProvider.future);
        for (final f in found) {
          final sid = f['systemId']!;
          final p = f['path'];

          final currentPath = await service.getSystemPath(sid);

          // Find system from the filtered list (already only contains systems with installed emus)
          final sysConf = systems.where((s) => s.system.id == sid).firstOrNull;
          if (sysConf == null) {
            developer.log('SETUP: Skipping $sid because no emulators are installed.', name: 'VaultSync', level: 800);
            skipped.add(sid);
            continue;
          }

          // Auto-selected mapped emulator from EmuDeck detection
          final mappedEmuId = f['emulatorId'];
          
          bool shouldOverride = currentPath == null;
          final isEmuDeckRoute = mappedEmuId != null && p != null && p.toLowerCase().contains('emulation/saves');

          if (!shouldOverride && isEmuDeckRoute && !(currentPath.toLowerCase().contains('emulation/saves') ?? false)) {
            shouldOverride = true;
          }
          
          if (!shouldOverride && Platform.isAndroid && p != null) {
            final isBrokenLegacy = (currentPath == p);
            final isGenericRA = (currentPath?.contains('RetroArch/saves') ?? false);
            final isStandalone = (mappedEmuId == null); 
            
            if (isBrokenLegacy || (isGenericRA && isStandalone)) {
               shouldOverride = true;
            }
          }

          if (shouldOverride) {
            final supportedEmus = sysConf.emulators.where((e) => e.isInstalled && PlatformUtils.isEmulatorSupported(e.uniqueId)).toList();
            
            EmulatorInfo? selectedEmu;
            if (mappedEmuId != null && mappedEmuId.isNotEmpty) {
              selectedEmu = supportedEmus.where((e) => e.uniqueId == mappedEmuId).firstOrNull;
            }
            
            selectedEmu ??= supportedEmus.firstWhere((e) => e.defaultEmulator, orElse: () => supportedEmus.isNotEmpty ? supportedEmus.first : sysConf.emulators.first);
            
            await service.setSystemEmulator(sid, selectedEmu.uniqueId);
            
            if (mappedEmuId != null && mappedEmuId.isNotEmpty && p != null) {
              await service.setSystemPath(sid, p);
            } else {
              final suggested = await service.suggestSavePath(selectedEmu, sid);
              await service.setSystemPath(sid, suggested);
            }
          }
        }
      }

      setState(() {
        _foundSystems = found;
        _skippedNoEmulator = skipped;
      });
      await _loadConfiguredPaths();
      ref.invalidate(systemPathsProvider);

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

    // Filter ONLY installed and supported emulators
    final supportedEmulators = system.emulators.where((e) => e.isInstalled && PlatformUtils.isEmulatorSupported(e.uniqueId)).toList();
    
    if (supportedEmulators.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No installed emulators found for ${system.system.name}.')),
      );
      return;
    }

    final selectedEmulatorId = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Select Emulator for ${system.system.name}'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: supportedEmulators.length,
            itemBuilder: (context, index) {
              final emu = supportedEmulators[index];
              final isSelected = emu.uniqueId == currentEmulatorId;
              return ListTile(
                title: Text(emu.name, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                subtitle: Text(emu.uniqueId, style: const TextStyle(fontSize: 10)),
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
    
    final mappedPath = _foundSystems.where((f) => f['systemId'] == systemId).firstOrNull?['path'];
    String initialPath;
    if (selectedEmulatorId != currentEmulatorId) {
      initialPath = mappedPath ?? await pathService.suggestSavePath(emulator, systemId);
    } else {
      initialPath = currentPath ?? mappedPath ?? await pathService.suggestSavePath(emulator, systemId);
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
                        if (pathController.text.startsWith('content://')) {
                          initialUri = pathController.text;
                        } else if (pathController.text.startsWith('/storage/emulated/0/')) {
                          String relPath = pathController.text.substring(20).replaceAll('/', '%2F');
                          if (pathController.text.contains('/Android/data/')) {
                            final parts = pathController.text.split('/Android/data/');
                            if (parts.length > 1) {
                              final packageName = parts[1].split('/').first;
                              relPath = 'Android%2Fdata%2F$packageName';
                            } else {
                              relPath = 'Android';
                            }
                          }
                          initialUri = 'content://com.android.externalstorage.documents/tree/primary%3A$relPath';
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
      final conflicts = await pathService.findPathConflicts(systemId, confirmedPath);
      if (conflicts.isNotEmpty) {
        if (!mounted) return;
        // _confirmPathOverlap re-checks `mounted` before touching context.
        // ignore: use_build_context_synchronously
        final proceed = await _confirmPathOverlap(system.system.name, conflicts);
        if (proceed != true) return;
      }

      await pathService.setSystemEmulator(systemId, selectedEmulatorId);
      await pathService.setSystemPath(systemId, confirmedPath);
      await _loadConfiguredPaths();
      ref.invalidate(systemPathsProvider);
      if (mounted) setState(() {});
    }
  }

  Future<bool?> _confirmPathOverlap(String systemName, List<String> conflictingIds) {
    if (!mounted) return Future.value(null);
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Path already in use'),
        content: Text(
          'The folder you picked for $systemName is already configured for: '
          '${conflictingIds.join(', ')}.\n\n'
          'Two systems sharing one folder will upload the same files under '
          'multiple system namespaces on the server (e.g. gc/ and nds/ both '
          'getting the same saves). Continue anyway?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Use anyway')),
        ],
      ),
    );
  }

  /// Shizuku is the single biggest lever on a fresh device: with it enabled every
  /// path is routed through the binder, so none of the `/Android/data` folders
  /// need a SAF grant and file timestamps can actually be written.
  ///
  /// The health readout is not decoration — a sync silently skips `shizuku://`
  /// systems when the binder is down, and Shizuku stops on every reboot.
  Widget _buildShizukuCard() {
    final status = _shizukuStatus;
    final healthy = status != null && status.isRunning && status.isAuthorized;
    final needsAction = _shizukuEnabled && !healthy;

    final String detail;
    if (!_shizukuEnabled) {
      detail = 'Recommended. Skips the per-folder permission prompts for '
          'emulators that store saves under Android/data, and lets VaultSync '
          'preserve file timestamps.';
    } else if (status == null) {
      detail = 'Checking Shizuku…';
    } else if (!status.isRunning) {
      detail = 'Shizuku is not running. Start it (wireless debugging), then '
          'come back — otherwise these systems are skipped without an error.';
    } else if (!status.isAuthorized) {
      detail = 'Shizuku is running but has not authorized VaultSync yet.';
    } else {
      detail = 'Connected. Restart Shizuku after every device reboot.';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 24),
      color: needsAction ? Colors.orange.withOpacity(0.12) : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _shizukuEnabled
                      ? (healthy ? Icons.verified_user : Icons.error_outline)
                      : Icons.shield_outlined,
                  color: _shizukuEnabled
                      ? (healthy ? Colors.green : Colors.orange)
                      : Colors.grey,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('Shizuku access',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                Switch(
                  value: _shizukuEnabled,
                  onChanged: (v) => _setShizukuEnabled(v),
                ),
              ],
            ),
            Text(detail,
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            if (needsAction)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _fixShizuku,
                  child: Text(status != null && !status.isRunning
                      ? 'OPEN SHIZUKU'
                      : 'AUTHORIZE'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Banner for systems that exist on disk but have no installed emulator.
  Widget _buildSkippedBanner() {
    return Container(
      width: double.infinity,
      color: Colors.orange.withOpacity(0.12),
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 18, color: Colors.orange),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${_skippedNoEmulator.length} system(s) found in your library with '
              'no emulator installed: ${_skippedNoEmulator.join(', ')}. Install '
              'them, then scan again.',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final pendingSaf = _pathsNeedingSaf;
    
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
                onPressed: () async {
                  ref.invalidate(systemPathsProvider);
                  await Future.delayed(const Duration(milliseconds: 300));
                  if (mounted) context.go('/dashboard');
                },
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('FINISH SETUP', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
        ],
      ),
      body: LayoutBuilder(builder: (context, constraints) {
        final content = [
          Container(
            width: isLandscape ? 320 : double.infinity,
            color: Colors.black26,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (Platform.isAndroid) _buildShizukuCard(),
                  const Text('SELECT ROMS ROOT',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.blue)),
                  const SizedBox(height: 8),
                  const Text('Base folder containing your game subfolders (e.g. Roms/ps2, Roms/snes).',
                      style: TextStyle(fontSize: 13, color: Colors.grey)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _pathController,
                    decoration: InputDecoration(
                      labelText: 'Path',
                      border: const OutlineInputBorder(),
                      isDense: true,
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.folder_open),
                        onPressed: _pickGlobalFolder,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 64,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue.withOpacity(0.3),
                          foregroundColor: Colors.white,
                      ),
                      onPressed: _isScanning ? null : _scan,
                      child: _isScanning
                          ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.search),
                                SizedBox(width: 12),
                                Text('SCAN LIBRARY',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              ],
                            ),
                    ),
                  ),
                  if (pendingSaf.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _grantingSaf ? null : _grantSafPermissions,
                      icon: _grantingSaf
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.lock_open),
                      label: Text(
                          'GRANT ${pendingSaf.length} FOLDER PERMISSION(S)'),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Do this now instead of being interrupted during the first '
                      'sync. Enabling Shizuku above avoids these prompts entirely.',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ],
              ),
            ),
          ),

          Expanded(
            flex: 1,
            child: _foundSystems.isEmpty 
              ? const Center(child: Text('No systems detected yet.\nSelect your ROMs root and click "Scan".', textAlign: TextAlign.center))
              : Column(
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                      child: Row(
                        children: [
                          Text('DETECTED SYSTEMS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    if (_skippedNoEmulator.isNotEmpty) _buildSkippedBanner(),
                    Expanded(
                      child: FutureBuilder<List<EmulatorConfig>>(
                        future: ref.watch(systemsProvider.future),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                          final foundIds = _foundSystems.map((e) => e['systemId']).toList();
                          final systems = snapshot.data!.where((s) => foundIds.contains(s.system.id)).toList();
                          
                          if (systems.isEmpty) {
                            return const Center(
                              child: Padding(
                                padding: EdgeInsets.all(24.0),
                                child: Text('No installed emulators found for the detected systems.', textAlign: TextAlign.center),
                              ),
                            );
                          }

                          return ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: systems.length,
                            itemBuilder: (context, index) {
                              final sys = systems[index];
                              final isConfigured = _configuredPaths.containsKey(sys.system.id);
                              // null while the reachability check is still running.
                              final reachable = _pathReachable[sys.system.id];

                              final String subtitle;
                              final Widget trailing;
                              if (!isConfigured) {
                                subtitle = 'Needs Setup';
                                trailing = const Icon(Icons.warning_amber_rounded,
                                    color: Colors.orange);
                              } else if (reachable == null) {
                                subtitle = 'Checking folder…';
                                trailing = const SizedBox(
                                    height: 16,
                                    width: 16,
                                    child:
                                        CircularProgressIndicator(strokeWidth: 2));
                              } else if (reachable) {
                                subtitle = 'Configured — folder verified';
                                trailing = const Icon(Icons.check_circle,
                                    color: Colors.green);
                              } else {
                                subtitle = "Configured — can't read this folder";
                                trailing = const Icon(Icons.error_outline,
                                    color: Colors.orange);
                              }

                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                child: ListTile(
                                  leading: Icon(
                                    Icons.gamepad,
                                    color: isConfigured ? Colors.blue : Colors.orange
                                  ),
                                  title: Text(sys.system.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                  subtitle: Text(
                                    subtitle,
                                    style: TextStyle(
                                      color: reachable == false
                                          ? Colors.orange
                                          : null,
                                    ),
                                  ),
                                  trailing: trailing,
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
          ),
        ];

        return isLandscape 
          ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: content)
          : Column(children: content);
      }),
    );
  }
}
