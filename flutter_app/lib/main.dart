import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';
import 'services/offline_queue_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  OfflineQueueService().startListening();
  runApp(const MagazynApp());
}

class MagazynApp extends StatelessWidget {
  const MagazynApp({super.key});

  static const Color accent = Color(0xFF3498DB);
  static const Color darkBg = Color(0xFF1C1E26);
  static const Color cardBg = Color(0xFF2C2F3A);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Magazyn - LogisticsERP',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: darkBg,
        colorSchemeSeed: accent,
        useMaterial3: true,
        cardTheme: CardThemeData(
          color: cardBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: darkBg,
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
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: MagazynApp.accent)),
      );
    }
    return _loggedIn ? const HomeScreen() : const LoginScreen();
  }
}
