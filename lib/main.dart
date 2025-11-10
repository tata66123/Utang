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

class _ProjectAppState extends State<ProjectApp> {
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    ServiceLocator().dataStore.load().then((_) => setState(() => _loaded = true));
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: ServiceLocator().dataStore,
      child: Consumer<DataStore>(
        builder: (context, dataStore, child) {
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
