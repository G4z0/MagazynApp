import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../models/code_type.dart';
import 'api_service.dart';
import 'auth_service.dart';

/// Serwis kolejki offline — zapisuje ruchy magazynowe lokalnie gdy brak sieci,
/// automatycznie wysyła gdy połączenie wróci.
class OfflineQueueService {
  static final OfflineQueueService _instance = OfflineQueueService._();
  factory OfflineQueueService() => _instance;
  OfflineQueueService._();

  Database? _db;
  StreamSubscription? _connectivitySub;
  bool _isSyncing = false;

  /// Liczba oczekujących elementów w kolejce (do UI)
  final ValueNotifier<int> pendingCount = ValueNotifier(0);

  Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    return openDatabase(
      p.join(dbPath, 'offline_queue.db'),
      version: 6,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE queue (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            barcode TEXT NOT NULL,
            code_type TEXT NOT NULL DEFAULT 'barcode',
            product_name TEXT NOT NULL,
            movement_type TEXT NOT NULL DEFAULT 'in',
            quantity REAL NOT NULL DEFAULT 1,
            unit TEXT NOT NULL DEFAULT 'szt',
            note TEXT,
            user_id INTEGER,
            user_name TEXT,
            issue_reason TEXT,
            vehicle_plate TEXT,
            issue_target TEXT,
            driver_id INTEGER,
            driver_name TEXT,
            created_at TEXT NOT NULL
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            "ALTER TABLE queue ADD COLUMN code_type TEXT NOT NULL DEFAULT 'barcode'",
          );
        }
        if (oldVersion < 3) {
          await db.execute(
            "ALTER TABLE queue ADD COLUMN movement_type TEXT NOT NULL DEFAULT 'in'",
          );
          await db.execute(
            "ALTER TABLE queue ADD COLUMN note TEXT",
          );
        }
        if (oldVersion < 4) {
          await db.execute(
            "ALTER TABLE queue ADD COLUMN user_id INTEGER",
          );
          await db.execute(
            "ALTER TABLE queue ADD COLUMN user_name TEXT",
          );
        }
        if (oldVersion < 5) {
          await db.execute(
            "ALTER TABLE queue ADD COLUMN issue_reason TEXT",
          );
          await db.execute(
            "ALTER TABLE queue ADD COLUMN vehicle_plate TEXT",
          );
        }
        if (oldVersion < 6) {
          await db.execute(
            "ALTER TABLE queue ADD COLUMN issue_target TEXT",
          );
          await db.execute(
            "ALTER TABLE queue ADD COLUMN driver_id INTEGER",
          );
          await db.execute(
            "ALTER TABLE queue ADD COLUMN driver_name TEXT",
          );
        }
      },
    );
  }

  /// Uruchom nasłuchiwanie zmian sieci
  void startListening() {
    _connectivitySub?.cancel();
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final hasConnection = results.any((r) => r != ConnectivityResult.none);
      if (hasConnection) {
        syncQueue();
      }
    });
    _refreshCount();
  }

  /// Zatrzymaj nasłuchiwanie
  void stopListening() {
    _connectivitySub?.cancel();
  }

  /// Dodaj ruch magazynowy do kolejki offline
  Future<void> enqueue({
    required String barcode,
    required String productName,
    required double quantity,
    required String unit,
    required CodeType codeType,
    required String movementType,
    String? note,
    String? issueReason,
    String? vehiclePlate,
    String? issueTarget,
    int? driverId,
    String? driverName,
  }) async {
    final db = await database;
    final auth = AuthService();
    await db.insert('queue', {
      'barcode': barcode,
      'code_type': codeType.apiValue,
      'product_name': productName,
      'movement_type': movementType,
      'quantity': quantity,
      'unit': unit,
      'note': note,
      'user_id': auth.userId,
      'user_name': auth.displayName,
      'issue_reason': issueReason,
      'vehicle_plate': vehiclePlate,
      'issue_target': issueTarget,
      'driver_id': driverId,
      'driver_name': driverName,
      'created_at': DateTime.now().toIso8601String(),
    });
    await _refreshCount();
  }

  /// Wyślij zakolejkowane ruchy na serwer
  Future<void> syncQueue() async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      final db = await database;
      final items = await db.query('queue', orderBy: 'id ASC');

      for (final item in items) {
        try {
          await ApiService.saveProduct(
            barcode: item['barcode'] as String,
            productName: item['product_name'] as String,
            quantity: (item['quantity'] as num).toDouble(),
            unit: item['unit'] as String,
            codeType: CodeType.fromApi(item['code_type'] as String?),
            movementType: item['movement_type'] as String? ?? 'in',
            note: item['note'] as String?,
            issueReason: item['issue_reason'] as String?,
            vehiclePlate: item['vehicle_plate'] as String?,
            issueTarget: item['issue_target'] as String?,
            driverId: item['driver_id'] as int?,
            driverName: item['driver_name'] as String?,
          );
          // Wysłano — usuń z kolejki
          await db.delete('queue', where: 'id = ?', whereArgs: [item['id']]);
          await _refreshCount();
        } on ApiException {
          // Błąd biznesowy (np. walidacja) — usuń, nie ma sensu ponawiać
          await db.delete('queue', where: 'id = ?', whereArgs: [item['id']]);
          await _refreshCount();
        } catch (_) {
          // Błąd sieci — przerwij, spróbuj następnym razem
          break;
        }
      }
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _refreshCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as cnt FROM queue');
    pendingCount.value = Sqflite.firstIntValue(result) ?? 0;
  }

  /// Pobierz wszystkie elementy z kolejki (do podglądu)
  Future<List<Map<String, dynamic>>> getAll() async {
    final db = await database;
    return db.query('queue', orderBy: 'id DESC');
  }

  /// Usuń element z kolejki
  Future<void> removeItem(int id) async {
    final db = await database;
    await db.delete('queue', where: 'id = ?', whereArgs: [id]);
    await _refreshCount();
  }
}
