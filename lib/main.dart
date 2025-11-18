import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/theme/app_theme.dart';
import 'core/services/data_store.dart';
import 'core/di/service_locator.dart';
import 'features/owner/pages/auth/login_page.dart';
import 'routes/role_based_navigation.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ServiceLocator().initialize();
  runApp(const ProjectApp());
}

class ProjectApp extends StatefulWidget {
  const ProjectApp({super.key});

  @override
  State<ProjectApp> createState() => _ProjectAppState();
}

class _ProjectAppState extends State<ProjectApp> with WidgetsBindingObserver {
  bool _loaded = false;
  bool _lastDarkMode = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ServiceLocator().dataStore.load().then((_) {
      if (mounted) {
        _lastDarkMode = ServiceLocator().dataStore.isDarkMode;
        setState(() => _loaded = true);
      }
    });
    // Listen to theme changes
    ServiceLocator().dataStore.addListener(_onThemeChanged);
  }

  void _onThemeChanged() {
    final currentDarkMode = ServiceLocator().dataStore.isDarkMode;
    if (currentDarkMode != _lastDarkMode) {
      _lastDarkMode = currentDarkMode;
      if (mounted) {
        setState(() {}); // Force rebuild when theme changes
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ServiceLocator().dataStore.removeListener(_onThemeChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    final dataStore = ServiceLocator().dataStore;
    
    // When app comes to foreground, restart listeners (they may have disconnected in background)
    // Real-time listeners will automatically fetch updates, no need for manual refresh
    if (state == AppLifecycleState.resumed && dataStore.state.currentUser != null) {
      // Restart real-time listeners - they will automatically sync when changes occur
      dataStore.restartRealtimeSync();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: ServiceLocator().dataStore,
      child: Consumer<DataStore>(
        builder: (context, dataStore, child) {
          // MaterialApp will rebuild automatically when themeMode changes via Consumer
          // No need for key change to avoid closing drawers/navigation
          return MaterialApp(
            title: 'Utang App',
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: dataStore.isDarkMode ? ThemeMode.dark : ThemeMode.light,
            debugShowCheckedModeBanner: false,
            home: _loaded 
                ? (dataStore.state.currentUser != null
                    ? const RoleBasedNavigation()
                    : const LoginPage())
                : const Scaffold(body: Center(child: CircularProgressIndicator())),
          );
        },
      ),
    );
  }
}
