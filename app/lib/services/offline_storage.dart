import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class OfflineStorage {
  static final OfflineStorage _instance = OfflineStorage._internal();
  factory OfflineStorage() => _instance;
  OfflineStorage._internal();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDB();
    return _db!;
  }

  Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'offline_detections.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE detections(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            imagePath TEXT,
            socialText TEXT,
            lat TEXT,
            lon TEXT,
            timestamp TEXT
          )
        ''');
      },
    );
  }

  Future<void> saveDetection({
    required String imagePath,
    required String socialText,
    required String lat,
    required String lon,
  }) async {
    final db = await database;
    await db.insert('detections', {
      'imagePath': imagePath,
      'socialText': socialText,
      'lat': lat,
      'lon': lon,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getPendingDetections() async {
    final db = await database;
    return await db.query('detections');
  }

  Future<void> deleteDetection(int id) async {
    final db = await database;
    await db.delete('detections', where: 'id = ?', whereArgs: [id]);
  }
}
