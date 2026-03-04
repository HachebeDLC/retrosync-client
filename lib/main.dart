import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';
import 'core/router/app_router.dart';
import 'core/theme/theme_provider.dart';
import 'features/sync/background/sync_worker.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Workmanager().initialize(
    callbackDispatcher,
  );
  
  runApp(
    const ProviderScope(
      child: NeoSyncApp(),
    ),
  );
}

class NeoSyncApp extends ConsumerWidget {
  const NeoSyncApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);
    
    return MaterialApp.router(
      title: 'NeoSync Secure',
      themeMode: themeMode,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.deepPurple, brightness: Brightness.light),
      darkTheme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.deepPurple, brightness: Brightness.dark),
      routerConfig: goRouter,
    );
  }
}