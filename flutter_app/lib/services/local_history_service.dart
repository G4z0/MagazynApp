import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

/// Lokalna historia działań na tym urządzeniu.
/// Przechowuje w SQLite każdą akcję wykonaną w aplikacji.
class LocalHistoryService {
  static final LocalHistoryService _instance = LocalHistoryService._();
  factory LocalHistoryService() => _instance;
  LocalHistoryService._();

  Database? _db;

  Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    return openDatabase(
      p.join(dbPath, 'local_history.db'),
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            action_type TEXT NOT NULL,
            title TEXT NOT NULL,
            subtitle TEXT,
            barcode TEXT,
            quantity REAL,
            unit TEXT,
            issue_target TEXT,
            vehicle_plate TEXT,
            driver_id INTEGER,
            driver_name TEXT,
            user_name TEXT,
            created_at TEXT NOT NULL
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE history ADD COLUMN issue_target TEXT');
          await db.execute('ALTER TABLE history ADD COLUMN vehicle_plate TEXT');
          await db.execute('ALTER TABLE history ADD COLUMN driver_id INTEGER');
          await db.execute('ALTER TABLE history ADD COLUMN driver_name TEXT');
        }
      },
    );
  }

  /// Dodaj wpis do historii
  Future<void> add({
    required String actionType,
    required String title,
    String? subtitle,
    String? barcode,
    double? quantity,
    String? unit,
    String? issueTarget,
    String? vehiclePlate,
    int? driverId,
    String? driverName,
    String? userName,
  }) async {
    final db = await database;
    await db.insert('history', {
      'action_type': actionType,
      'title': title,
      'subtitle': subtitle,
      'barcode': barcode,
      'quantity': quantity,
      'unit': unit,
      'issue_target': issueTarget,
      'vehicle_plate': vehiclePlate,
      'driver_id': driverId,
      'driver_name': driverName,
      'user_name': userName,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// Pobierz historię (ostatnie N wpisów)
  Future<List<Map<String, dynamic>>> getHistory({int limit = 100}) async {
    final db = await database;
    return db.query(
      'history',
      orderBy: 'created_at DESC',
      limit: limit,
    );
  }

  /// Wyczyść całą historię
  Future<void> clear() async {
    final db = await database;
    await db.delete('history');
  }

  /// Liczba wpisów
  Future<int> count() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as cnt FROM history');
    return (result.first['cnt'] as int?) ?? 0;
  }
}
