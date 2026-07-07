import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class LocalDatabase {
  static final LocalDatabase instance = LocalDatabase._init();
  static Database? _database;

  LocalDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('internship.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 5,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('DROP TABLE IF EXISTS users');
      await db.execute('DROP TABLE IF EXISTS staff');
      await db.execute('DROP TABLE IF EXISTS profiles');
      await db.execute('DROP TABLE IF EXISTS log_entries');
      await db.execute('DROP TABLE IF EXISTS media_attachments');
      await _createDB(db, newVersion);
      return;
    }

    // Explicitly create tables if they were missed in version 2, 3, or 4
    if (oldVersion < 5) {
      const uuidType = 'TEXT PRIMARY KEY';
      const textType = 'TEXT NOT NULL';
      const boolType = 'INTEGER NOT NULL';
      const timestampType = 'TEXT NOT NULL';
      const nullableTextType = 'TEXT';

      await db.execute('''
        CREATE TABLE IF NOT EXISTS companies (
          id $uuidType,
          name $textType,
          address $nullableTextType,
          contact_person $nullableTextType,
          email $nullableTextType,
          updated_at $timestampType,
          is_dirty $boolType,
          is_deleted $boolType
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS app_settings (
          id TEXT PRIMARY KEY,
          key TEXT UNIQUE,
          value TEXT,
          updated_at $timestampType,
          is_dirty $boolType
        )
      ''');
    }
  }

  Future _createDB(Database db, int version) async {
    const uuidType = 'TEXT PRIMARY KEY';
    const textType = 'TEXT NOT NULL';
    const boolType = 'INTEGER NOT NULL';
    const timestampType = 'TEXT NOT NULL';
    const nullableTextType = 'TEXT';

    // Profiles Table (Unified)
    await db.execute('''
      CREATE TABLE profiles (
        id $uuidType,
        full_name $nullableTextType,
        role $nullableTextType,
        supervisor_id $nullableTextType,
        industry_supervisor_id $nullableTextType,
        department $nullableTextType,
        student_id_number $nullableTextType,
        company_name $nullableTextType,
        status $nullableTextType,
        updated_at $timestampType,
        is_dirty $boolType,
        is_deleted $boolType
      )
    ''');

    // Log Entries Table
    await db.execute('''
      CREATE TABLE log_entries (
        id $uuidType,
        student_id $textType,
        supervisor_id $nullableTextType,
        date $textType,
        day_number INTEGER,
        work_description $textType,
        knowledge_acquired $textType,
        recommendation $nullableTextType,
        status $textType,
        score INTEGER,
        updated_at $timestampType,
        is_dirty $boolType,
        is_deleted $boolType
      )
    ''');

    // Media Attachments Table
    await db.execute('''
      CREATE TABLE media_attachments (
        id $uuidType,
        log_id $textType,
        local_path $textType,
        remote_url $nullableTextType,
        file_type $textType,
        updated_at $timestampType,
        is_dirty $boolType,
        is_deleted $boolType
      )
    ''');

    // Companies Table
    await db.execute('''
      CREATE TABLE companies (
        id $uuidType,
        name $textType,
        address $nullableTextType,
        contact_person $nullableTextType,
        email $nullableTextType,
        updated_at $timestampType,
        is_dirty $boolType,
        is_deleted $boolType
      )
    ''');

    // App Settings Table
    await db.execute('''
      CREATE TABLE app_settings (
        id TEXT PRIMARY KEY,
        key TEXT UNIQUE,
        value TEXT,
        updated_at $timestampType,
        is_dirty $boolType
      )
    ''');
  }
}
