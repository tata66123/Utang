import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/models.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'utang_app.db');
    return await openDatabase(
      path,
      version: 8, // Increment: add creditLimit to users table
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // Users table
    await db.execute('''
      CREATE TABLE users (
        id TEXT PRIMARY KEY,
        email TEXT NOT NULL,
        username TEXT NOT NULL,
        storeName TEXT NOT NULL,
        role TEXT NOT NULL,
        password TEXT,
        creditLimit REAL,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL
      )
    ''');

    // Customers table
    await db.execute('''
      CREATE TABLE customers (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        storeId TEXT,
        creditLimit REAL,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        synced INTEGER DEFAULT 0
      )
    ''');

    // Credits table
    await db.execute('''
      CREATE TABLE credits (
        id TEXT PRIMARY KEY,
        customerId TEXT NOT NULL,
        storeId TEXT,
        item TEXT NOT NULL,
        amount REAL NOT NULL,
        quantity INTEGER DEFAULT 1,
        unitPrice REAL,
        date TEXT NOT NULL,
        dueDate TEXT,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        synced INTEGER DEFAULT 0,
        FOREIGN KEY (customerId) REFERENCES customers (id)
      )
    ''');

    // Payments table
    await db.execute('''
      CREATE TABLE payments (
        id TEXT PRIMARY KEY,
        creditId TEXT NOT NULL,
        amount REAL NOT NULL,
        date TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        synced INTEGER DEFAULT 0,
        FOREIGN KEY (creditId) REFERENCES credits (id)
      )
    ''');

    // Sync status table
    await db.execute('''
      CREATE TABLE sync_status (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        lastSync TEXT,
        isOnline INTEGER DEFAULT 0
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Add role column to users table
      await db.execute('ALTER TABLE users ADD COLUMN role TEXT NOT NULL DEFAULT "storeOwner"');
    }
    if (oldVersion < 3) {
      // Remove phone column from customers table
      // SQLite doesn't support DROP COLUMN directly, so we need to recreate the table
      await db.execute('''
        CREATE TABLE customers_new (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          createdAt TEXT NOT NULL,
          updatedAt TEXT NOT NULL,
          synced INTEGER DEFAULT 0
        )
      ''');
      
      // Copy data from old table to new table
      await db.execute('''
        INSERT INTO customers_new (id, name, createdAt, updatedAt, synced)
        SELECT id, name, createdAt, updatedAt, synced FROM customers
      ''');
      
      // Drop old table and rename new table
      await db.execute('DROP TABLE customers');
      await db.execute('ALTER TABLE customers_new RENAME TO customers');
    }
    if (oldVersion < 4) {
      // Add storeId to credits
      await db.execute('ALTER TABLE credits ADD COLUMN storeId TEXT');
    }
    if (oldVersion < 5) {
      // Add storeId to customers
      await db.execute('ALTER TABLE customers ADD COLUMN storeId TEXT');
    }
    if (oldVersion < 6) {
      // Add creditLimit to customers
      await db.execute('ALTER TABLE customers ADD COLUMN creditLimit REAL');
    }
    if (oldVersion < 7) {
      // Add quantity and unitPrice to credits
      await db.execute('ALTER TABLE credits ADD COLUMN quantity INTEGER DEFAULT 1');
      await db.execute('ALTER TABLE credits ADD COLUMN unitPrice REAL');
    }
    if (oldVersion < 8) {
      // Add creditLimit to users table (for store owners)
      await db.execute('ALTER TABLE users ADD COLUMN creditLimit REAL');
    }
  }

  // User operations
  Future<void> insertUser(User user) async {
    final db = await database;
    await db.insert('users', {
      'id': user.id,
      'email': user.email,
      'username': user.username,
      'storeName': user.storeName,
      'role': user.role.name,
      'password': user.password,
      'creditLimit': user.creditLimit,
      'createdAt': DateTime.now().toIso8601String(),
      'updatedAt': DateTime.now().toIso8601String(),
    });
  }

  Future<void> insertOrReplaceUser(User user) async {
    final db = await database;
    await db.insert('users', {
      'id': user.id,
      'email': user.email,
      'username': user.username,
      'storeName': user.storeName,
      'role': user.role.name,
      'password': user.password,
      'creditLimit': user.creditLimit,
      'createdAt': DateTime.now().toIso8601String(),
      'updatedAt': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<User?> getUserByUsername(String username) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'users',
      where: 'username = ?',
      whereArgs: [username],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return User.fromJson(maps.first);
  }

  Future<User?> getUserById(String userId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'users',
      where: 'id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return User.fromJson(maps.first);
  }

  Future<User?> getUser() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('users', limit: 1);
    if (maps.isEmpty) return null;
    return User.fromJson(maps.first);
  }

  Future<void> updateUser(User user) async {
    final db = await database;
    await db.update(
      'users',
      {
        'email': user.email,
        'username': user.username,
        'storeName': user.storeName,
        'role': user.role.name,
        'password': user.password,
        'creditLimit': user.creditLimit,
        'updatedAt': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [user.id],
    );
  }

  Future<void> deleteUser(String userId) async {
    final db = await database;
    await db.delete('users', where: 'id = ?', whereArgs: [userId]);
  }

  Future<void> deleteAllUsers() async {
    final db = await database;
    await db.delete('users');
  }

  // Customer operations
  Future<void> insertCustomer(Customer customer, {bool markAsSynced = false}) async {
    final db = await database;
    await db.insert('customers', {
      'id': customer.id,
      'name': customer.name,
      'storeId': customer.storeId,
      'creditLimit': customer.creditLimit,
      'createdAt': DateTime.now().toIso8601String(),
      'updatedAt': DateTime.now().toIso8601String(),
      'synced': markAsSynced ? 1 : 0,
    });
  }

  Future<void> insertOrReplaceCustomer(Customer customer, {bool markAsSynced = false}) async {
    final db = await database;
    await db.insert('customers', {
      'id': customer.id,
      'name': customer.name,
      'storeId': customer.storeId,
      'creditLimit': customer.creditLimit,
      'createdAt': DateTime.now().toIso8601String(),
      'updatedAt': DateTime.now().toIso8601String(),
      'synced': markAsSynced ? 1 : 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Customer>> getAllCustomers() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('customers');
    return List.generate(maps.length, (i) => Customer.fromJson(maps[i]));
  }

  Future<List<Customer>> getCustomersByStoreId(String storeId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'customers',
      where: 'storeId = ?',
      whereArgs: [storeId],
    );
    return List.generate(maps.length, (i) => Customer.fromJson(maps[i]));
  }

  Future<List<Customer>> getCustomersByIds(List<String> customerIds) async {
    if (customerIds.isEmpty) return [];
    final db = await database;
    final placeholders = customerIds.map((_) => '?').join(',');
    final List<Map<String, dynamic>> maps = await db.query(
      'customers',
      where: 'id IN ($placeholders)',
      whereArgs: customerIds,
    );
    return List.generate(maps.length, (i) => Customer.fromJson(maps[i]));
  }

  Future<Customer?> getCustomerById(String customerId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'customers',
      where: 'id = ?',
      whereArgs: [customerId],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return Customer.fromJson(maps[0]);
  }

  Future<void> updateCustomer(Customer customer) async {
    final db = await database;
    await db.update(
      'customers',
      {
        'name': customer.name,
        'storeId': customer.storeId,
        'creditLimit': customer.creditLimit,
        'updatedAt': DateTime.now().toIso8601String(),
        'synced': 0,
      },
      where: 'id = ?',
      whereArgs: [customer.id],
    );
  }

  Future<void> deleteCustomer(String customerId) async {
    final db = await database;
    await db.delete('customers', where: 'id = ?', whereArgs: [customerId]);
    await db.delete('credits', where: 'customerId = ?', whereArgs: [customerId]);
  }

  // Credit operations
  Future<void> insertCredit(CreditEntry credit, {bool markAsSynced = false}) async {
    final db = await database;
    await db.insert('credits', {
      'id': credit.id,
      'customerId': credit.customerId,
      'storeId': credit.storeId,
      'item': credit.item,
      'amount': credit.amount,
      'quantity': credit.quantity,
      'unitPrice': credit.unitPrice,
      'date': credit.date.toIso8601String(),
      'dueDate': credit.dueDate?.toIso8601String(),
      'createdAt': DateTime.now().toIso8601String(),
      'updatedAt': DateTime.now().toIso8601String(),
      'synced': markAsSynced ? 1 : 0,
    });

    // Insert payments
    for (final payment in credit.payments) {
      await db.insert('payments', {
        'id': payment.id,
        'creditId': credit.id,
        'amount': payment.amount,
        'date': payment.date.toIso8601String(),
        'createdAt': DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
        'synced': markAsSynced ? 1 : 0,
      });
    }
  }

  Future<void> insertOrReplaceCredit(CreditEntry credit, {bool markAsSynced = false}) async {
    final db = await database;
    await db.insert('credits', {
      'id': credit.id,
      'customerId': credit.customerId,
      'storeId': credit.storeId,
      'item': credit.item,
      'amount': credit.amount,
      'quantity': credit.quantity,
      'unitPrice': credit.unitPrice,
      'date': credit.date.toIso8601String(),
      'dueDate': credit.dueDate?.toIso8601String(),
      'createdAt': DateTime.now().toIso8601String(),
      'updatedAt': DateTime.now().toIso8601String(),
      'synced': markAsSynced ? 1 : 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    await db.delete('payments', where: 'creditId = ?', whereArgs: [credit.id]);
    for (final payment in credit.payments) {
      await db.insert('payments', {
        'id': payment.id,
        'creditId': credit.id,
        'amount': payment.amount,
        'date': payment.date.toIso8601String(),
        'createdAt': DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
        'synced': markAsSynced ? 1 : 0,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<List<CreditEntry>> getAllCredits() async {
    final db = await database;
    final List<Map<String, dynamic>> creditMaps = await db.query('credits');
    
    List<CreditEntry> credits = [];
    for (final creditMap in creditMaps) {
      final List<Map<String, dynamic>> paymentMaps = await db.query(
        'payments',
        where: 'creditId = ?',
        whereArgs: [creditMap['id']],
      );
      
      final List<Payment> payments = paymentMaps.map((map) => Payment.fromJson(map)).toList();
      
      final credit = CreditEntry(
        id: creditMap['id'],
        customerId: creditMap['customerId'],
        storeId: creditMap['storeId'],
        item: creditMap['item'],
        amount: creditMap['amount'],
        quantity: creditMap['quantity'] != null ? (creditMap['quantity'] as num).toInt() : 1,
        unitPrice: creditMap['unitPrice'] != null ? (creditMap['unitPrice'] as num).toDouble() : null,
        date: DateTime.parse(creditMap['date']),
        dueDate: creditMap['dueDate'] != null ? DateTime.parse(creditMap['dueDate']) : null,
      );
      
      credit.payments.addAll(payments);
      credits.add(credit);
    }
    
    return credits;
  }

  Future<List<CreditEntry>> getCreditsByStoreId(String storeId) async {
    final db = await database;
    final List<Map<String, dynamic>> creditMaps = await db.query(
      'credits',
      where: 'storeId = ?',
      whereArgs: [storeId],
    );
    List<CreditEntry> credits = [];
    for (final creditMap in creditMaps) {
      final List<Map<String, dynamic>> paymentMaps = await db.query(
        'payments',
        where: 'creditId = ?',
        whereArgs: [creditMap['id']],
      );
      final List<Payment> payments = paymentMaps.map((map) => Payment.fromJson(map)).toList();
      final credit = CreditEntry(
        id: creditMap['id'],
        customerId: creditMap['customerId'],
        storeId: creditMap['storeId'],
        item: creditMap['item'],
        amount: creditMap['amount'],
        quantity: creditMap['quantity'] != null ? (creditMap['quantity'] as num).toInt() : 1,
        unitPrice: creditMap['unitPrice'] != null ? (creditMap['unitPrice'] as num).toDouble() : null,
        date: DateTime.parse(creditMap['date']),
        dueDate: creditMap['dueDate'] != null ? DateTime.parse(creditMap['dueDate']) : null,
      );
      credit.payments.addAll(payments);
      credits.add(credit);
    }
    return credits;
  }

  Future<List<CreditEntry>> getCreditsByCustomerId(String customerId) async {
    final db = await database;
    final List<Map<String, dynamic>> creditMaps = await db.query(
      'credits',
      where: 'customerId = ?',
      whereArgs: [customerId],
    );
    List<CreditEntry> credits = [];
    for (final creditMap in creditMaps) {
      final List<Map<String, dynamic>> paymentMaps = await db.query(
        'payments',
        where: 'creditId = ?',
        whereArgs: [creditMap['id']],
      );
      final List<Payment> payments = paymentMaps.map((map) => Payment.fromJson(map)).toList();
      final credit = CreditEntry(
        id: creditMap['id'],
        customerId: creditMap['customerId'],
        storeId: creditMap['storeId'],
        item: creditMap['item'],
        amount: creditMap['amount'],
        quantity: creditMap['quantity'] != null ? (creditMap['quantity'] as num).toInt() : 1,
        unitPrice: creditMap['unitPrice'] != null ? (creditMap['unitPrice'] as num).toDouble() : null,
        date: DateTime.parse(creditMap['date']),
        dueDate: creditMap['dueDate'] != null ? DateTime.parse(creditMap['dueDate']) : null,
      );
      credit.payments.addAll(payments);
      credits.add(credit);
    }
    return credits;
  }

  Future<void> updateCredit(CreditEntry credit) async {
    final db = await database;
    await db.update(
      'credits',
      {
        'customerId': credit.customerId,
        'storeId': credit.storeId,
        'item': credit.item,
        'amount': credit.amount,
        'quantity': credit.quantity,
        'unitPrice': credit.unitPrice,
        'date': credit.date.toIso8601String(),
        'dueDate': credit.dueDate?.toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
        'synced': 0,
      },
      where: 'id = ?',
      whereArgs: [credit.id],
    );

    // Update payments
    await db.delete('payments', where: 'creditId = ?', whereArgs: [credit.id]);
    for (final payment in credit.payments) {
      await db.insert('payments', {
        'id': payment.id,
        'creditId': credit.id,
        'amount': payment.amount,
        'date': payment.date.toIso8601String(),
        'createdAt': DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
        'synced': 0,
      });
    }
  }

  Future<void> deleteCredit(String creditId) async {
    final db = await database;
    await db.delete('credits', where: 'id = ?', whereArgs: [creditId]);
    await db.delete('payments', where: 'creditId = ?', whereArgs: [creditId]);
  }

  // Payment operations
  Future<void> insertPayment(Payment payment, String creditId) async {
    final db = await database;
    await db.insert('payments', {
      'id': payment.id,
      'creditId': creditId,
      'amount': payment.amount,
      'date': payment.date.toIso8601String(),
      'createdAt': DateTime.now().toIso8601String(),
      'updatedAt': DateTime.now().toIso8601String(),
      'synced': 0,
    });
  }

  // Sync operations
  Future<void> markAsSynced(String table, String id) async {
    final db = await database;
    await db.update(
      table,
      {'synced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Map<String, dynamic>>> getUnsyncedRecords(String table) async {
    final db = await database;
    return await db.query(table, where: 'synced = ?', whereArgs: [0]);
  }

  Future<void> updateSyncStatus(bool isOnline, {DateTime? lastSync}) async {
    final db = await database;
    await db.delete('sync_status');
    await db.insert('sync_status', {
      'lastSync': lastSync?.toIso8601String(),
      'isOnline': isOnline ? 1 : 0,
    });
  }

  Future<Map<String, dynamic>?> getSyncStatus() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('sync_status', limit: 1);
    return maps.isEmpty ? null : maps.first;
  }

  // Clear data that doesn't belong to the current user (for data isolation)
  Future<void> clearDataForOtherStores(String currentStoreId) async {
    final db = await database;
    
    // First, get all credit IDs that belong to this store (before deleting)
    final validCreditMaps = await db.query(
      'credits',
      columns: ['id'],
      where: 'storeId = ?',
      whereArgs: [currentStoreId],
    );
    final Set<String> validCreditIds = validCreditMaps.map((m) => m['id'] as String).toSet();
    
    // Get all credit customer IDs for this store
    final creditMaps = await db.query(
      'credits',
      columns: ['customerId'],
      where: 'storeId = ?',
      whereArgs: [currentStoreId],
    );
    final Set<String> validCustomerIds = creditMaps.map((m) => m['customerId'] as String).toSet();
    
    // Delete customers that:
    // 1. Have a storeId that's not the current store
    // NOTE: We keep customers with null storeId even if they don't have credits yet,
    // because they might be customers created by customers that haven't received credits yet
    final allCustomers = await db.query('customers');
    final List<String> customersToDelete = [];
    
    for (final customer in allCustomers) {
      final customerStoreId = customer['storeId'] as String?;
      final customerId = customer['id'] as String;
      
      if (customerStoreId != null && customerStoreId != currentStoreId) {
        // Customer belongs to another store - delete
        customersToDelete.add(customerId);
      }
      // Don't delete customers with null storeId - they might be customers created by customers
      // They will be visible to store owners when they search/add credit
    }
    
    // Delete customers that don't belong
    if (customersToDelete.isNotEmpty) {
      final placeholders = customersToDelete.map((_) => '?').join(',');
      await db.delete(
        'customers',
        where: 'id IN ($placeholders)',
        whereArgs: customersToDelete,
      );
    }
    
    // Delete credits that don't belong to this store
    await db.delete(
      'credits',
      where: 'storeId != ? OR (storeId IS NULL)',
      whereArgs: [currentStoreId],
    );
    
    // Delete payments for credits that were deleted (not in validCreditIds)
    if (validCreditIds.isNotEmpty) {
      final placeholders = validCreditIds.map((_) => '?').join(',');
      await db.delete(
        'payments',
        where: 'creditId NOT IN ($placeholders)',
        whereArgs: validCreditIds.toList(),
      );
    } else {
      // No valid credits left, delete all payments
      await db.delete('payments');
    }
  }

  Future<void> clearDataForOtherCustomers(String currentCustomerId) async {
    final db = await database;
    
    // First, get all credit IDs that belong to this customer (before deleting)
    final validCreditMaps = await db.query(
      'credits',
      columns: ['id'],
      where: 'customerId = ?',
      whereArgs: [currentCustomerId],
    );
    final Set<String> validCreditIds = validCreditMaps.map((m) => m['id'] as String).toSet();
    
    // Delete customers that aren't this customer
    await db.delete(
      'customers',
      where: 'id != ?',
      whereArgs: [currentCustomerId],
    );
    
    // Delete credits that don't belong to this customer
    await db.delete(
      'credits',
      where: 'customerId != ?',
      whereArgs: [currentCustomerId],
    );
    
    // Delete payments for credits that were deleted (not in validCreditIds)
    if (validCreditIds.isNotEmpty) {
      final placeholders = validCreditIds.map((_) => '?').join(',');
      await db.delete(
        'payments',
        where: 'creditId NOT IN ($placeholders)',
        whereArgs: validCreditIds.toList(),
      );
    } else {
      // No valid credits left, delete all payments
      await db.delete('payments');
    }
  }

  Future<void> clearAllData() async {
    final db = await database;
    await db.delete('users');
    await db.delete('customers');
    await db.delete('credits');
    await db.delete('payments');
    await db.delete('sync_status');
  }
}
