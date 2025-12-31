import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:monoc_locsaver/models/location_record.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('locations.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(path, version: 3, onCreate: _createDB, onUpgrade: _upgradeDB);
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
CREATE TABLE locations ( 
  id INTEGER PRIMARY KEY AUTOINCREMENT, 
  latitude REAL NOT NULL,
  longitude REAL NOT NULL,
  timestamp TEXT NOT NULL,
  note TEXT,
  image_path TEXT,
  speed REAL,
  accuracy REAL,
  transport_mode TEXT,
  is_stay_point INTEGER DEFAULT 0,
  stay_duration_minutes INTEGER,
  place_name TEXT,
  place_type TEXT,
  address TEXT,
  road_type TEXT,
  is_highway INTEGER DEFAULT 0,
  is_railway INTEGER DEFAULT 0
  )
''');
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE locations ADD COLUMN speed REAL');
      await db.execute('ALTER TABLE locations ADD COLUMN accuracy REAL');
      await db.execute('ALTER TABLE locations ADD COLUMN transport_mode TEXT');
      await db.execute('ALTER TABLE locations ADD COLUMN is_stay_point INTEGER DEFAULT 0');
      await db.execute('ALTER TABLE locations ADD COLUMN stay_duration_minutes INTEGER');
      await db.execute('ALTER TABLE locations ADD COLUMN place_name TEXT');
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE locations ADD COLUMN place_type TEXT');
      await db.execute('ALTER TABLE locations ADD COLUMN address TEXT');
      await db.execute('ALTER TABLE locations ADD COLUMN road_type TEXT');
      await db.execute('ALTER TABLE locations ADD COLUMN is_highway INTEGER DEFAULT 0');
      await db.execute('ALTER TABLE locations ADD COLUMN is_railway INTEGER DEFAULT 0');
    }
  }

  Future<LocationRecord> create(LocationRecord record) async {
    final db = await instance.database;
    final id = await db.insert('locations', record.toMap());
    return record.copyWith(id: id);
  }

  Future<int> update(LocationRecord record) async {
    final db = await instance.database;
    return await db.update(
      'locations',
      record.toMap(),
      where: 'id = ?',
      whereArgs: [record.id],
    );
  }

  Future<List<LocationRecord>> readAllLocations() async {
    final db = await instance.database;
    const orderBy = 'timestamp DESC';
    final result = await db.query('locations', orderBy: orderBy);
    return result.map((json) => LocationRecord.fromMap(json)).toList();
  }

  Future<List<LocationRecord>> readLocationsByDate(DateTime date) async {
    final db = await instance.database;
    final start = DateTime(date.year, date.month, date.day).toIso8601String();
    final end = DateTime(date.year, date.month, date.day, 23, 59, 59).toIso8601String();
    
    final result = await db.query(
      'locations',
      where: 'timestamp BETWEEN ? AND ?',
      whereArgs: [start, end],
      orderBy: 'timestamp ASC',
    );
    return result.map((json) => LocationRecord.fromMap(json)).toList();
  }

  Future<LocationRecord?> getLastRecord() async {
    final db = await instance.database;
    final result = await db.query(
      'locations',
      orderBy: 'timestamp DESC',
      limit: 1,
    );
    if (result.isEmpty) return null;
    return LocationRecord.fromMap(result.first);
  }

  Future<List<LocationRecord>> getStayPoints(DateTime date) async {
    final db = await instance.database;
    final start = DateTime(date.year, date.month, date.day).toIso8601String();
    final end = DateTime(date.year, date.month, date.day, 23, 59, 59).toIso8601String();
    
    final result = await db.query(
      'locations',
      where: 'timestamp BETWEEN ? AND ? AND is_stay_point = 1',
      whereArgs: [start, end],
      orderBy: 'timestamp ASC',
    );
    return result.map((json) => LocationRecord.fromMap(json)).toList();
  }

  Future<int> delete(int id) async {
    final db = await instance.database;
    return await db.delete(
      'locations',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
