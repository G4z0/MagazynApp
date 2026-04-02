import 'package:flutter/material.dart';
import 'screens/scanner_screen.dart';
import 'services/offline_queue_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  OfflineQueueService().startListening();
  runApp(const BarcodeApp());
}

class BarcodeApp extends StatelessWidget {
  const BarcodeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Skaner Kodów - LogisticsERP',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF1565C0),
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      home: const ScannerScreen(),
    );
  }
}
