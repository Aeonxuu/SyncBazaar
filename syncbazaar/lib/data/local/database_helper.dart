import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  DatabaseHelper._();

  static final DatabaseHelper instance = DatabaseHelper._();
  static Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDatabase();
    return _db!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    return openDatabase(
      join(dbPath, 'syncbazaar.db'),
      version: 2,
      onCreate: (db, version) async {
        await _createSchema(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('DROP TABLE IF EXISTS Notification');
          await db.execute('DROP TABLE IF EXISTS ApprovalRequest');
          await db.execute('DROP TABLE IF EXISTS "Order"');
          await db.execute('DROP TABLE IF EXISTS Sale');
          await db.execute('DROP TABLE IF EXISTS EventInventory');
          await db.execute('DROP TABLE IF EXISTS ProductVariantOption');
          await db.execute('DROP TABLE IF EXISTS ProductVariantGroup');
          await db.execute('DROP TABLE IF EXISTS Product');
          await db.execute('DROP TABLE IF EXISTS Category');
          await db.execute('DROP TABLE IF EXISTS BazaarEvent');
          await db.execute('DROP TABLE IF EXISTS Company');
          await db.execute('DROP TABLE IF EXISTS User');
          await _createSchema(db);
        }
      },
    );
  }

  Future<void> _createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE User(
        id INTEGER PRIMARY KEY,
        name TEXT,
        email TEXT,
        role TEXT,
        assigned_event_id INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE Company(
        id INTEGER PRIMARY KEY,
        name TEXT,
        address TEXT,
        contact TEXT,
        incentive_percent REAL,
        buffer_percent REAL,
        qr_image_path TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE BazaarEvent(
        id INTEGER PRIMARY KEY,
        name TEXT,
        company_id INTEGER,
        start_date TEXT,
        end_date TEXT,
        status TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE Category(
        id INTEGER PRIMARY KEY,
        name TEXT,
        description TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE Product(
        id INTEGER PRIMARY KEY,
        name TEXT,
        description TEXT,
        category_id INTEGER,
        base_price REAL,
        image_path TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE ProductVariantGroup(
        id INTEGER PRIMARY KEY,
        product_id INTEGER,
        name TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE ProductVariantOption(
        id INTEGER PRIMARY KEY,
        variant_group_id INTEGER,
        value TEXT,
        extra_price REAL
      )
    ''');
    await db.execute('''
      CREATE TABLE EventInventory(
        id INTEGER PRIMARY KEY,
        event_id INTEGER,
        product_id INTEGER,
        variant_option_id INTEGER,
        allocated_quantity INTEGER,
        sold_quantity INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE Sale(
        id INTEGER PRIMARY KEY,
        event_id INTEGER,
        product_id INTEGER,
        variant_option_id INTEGER,
        customer_name TEXT,
        employee_id TEXT,
        payment_method TEXT,
        qty INTEGER,
        total REAL,
        timestamp TEXT,
        order_status TEXT,
        synced INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE "Order"(
        id INTEGER PRIMARY KEY,
        sale_id INTEGER,
        event_id INTEGER,
        order_status TEXT,
        updated_at TEXT,
        synced INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE ApprovalRequest(
        id INTEGER PRIMARY KEY,
        type TEXT,
        event_id INTEGER,
        requester_id INTEGER,
        status TEXT,
        details_json TEXT,
        synced INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE Notification(
        id INTEGER PRIMARY KEY,
        type TEXT,
        message TEXT,
        created_at TEXT,
        read INTEGER
      )
    ''');
  }
}
