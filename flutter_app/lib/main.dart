import 'package:flutter/material.dart';
import 'l10n/translations.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';
import 'services/offline_queue_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initTranslations();
  OfflineQueueService().startListening();
  runApp(MagazynApp());
}

class MagazynApp extends StatefulWidget {
  MagazynApp({super.key});

  static const Color accent = Color(0xFF3498DB);
  static const Color darkBg = Color(0xFF1C1E26);
  static const Color cardBg = Color(0xFF2C2F3A);

  static final _navKey = GlobalKey<NavigatorState>();
  static GlobalKey<NavigatorState> get navKey => _navKey;

  /// Call after setLanguage() to rebuild the entire widget tree.
  static void restartApp(BuildContext context) {
    context.findAncestorStateOfType<_MagazynAppState>()?.restart();
  }

  @override
  State<MagazynApp> createState() => _MagazynAppState();
}

class _MagazynAppState extends State<MagazynApp> {
  Key _appKey = UniqueKey();

  void restart() => setState(() => _appKey = UniqueKey());

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      key: _appKey,
      navigatorKey: MagazynApp.navKey,
      title: tr('APP_TITLE'),
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: MagazynApp.darkBg,
        colorSchemeSeed: MagazynApp.accent,
        useMaterial3: true,
        cardTheme: CardThemeData(
          color: MagazynApp.cardBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: MagazynApp.darkBg,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),
      home: const _AuthGate(),
    );
  }
}

class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  bool _checking = true;
  bool _loggedIn = false;

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    final loggedIn = await AuthService().loadSession();
    if (mounted) setState(() { _loggedIn = loggedIn; _checking = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset('assets/logo.png', width: 220),
              const SizedBox(height: 32),
              const CircularProgressIndicator(color: MagazynApp.accent),
            ],
          ),
        ),
      );
    }
    return _loggedIn ? const HomeScreen() : const LoginScreen();
  }
}
