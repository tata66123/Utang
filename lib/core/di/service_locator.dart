import '../services/data_store.dart';
import '../services/firebase_service.dart';
import '../services/notification_service.dart';
import '../services/sync_service.dart';
import '../database/database_helper.dart';

/// Dependency Injection Container following OOP principles
class ServiceLocator {
  static final ServiceLocator _instance = ServiceLocator._internal();
  factory ServiceLocator() => _instance;
  ServiceLocator._internal();

  // Service instances
  DataStore? _dataStore;
  FirebaseService? _firebaseService;
  NotificationService? _notificationService;
  SyncService? _syncService;
  DatabaseHelper? _databaseHelper;

  /// Initialize all services and dependencies
  Future<void> initialize() async {
    // Initialize core services
    _databaseHelper = DatabaseHelper();
    _firebaseService = FirebaseService();
    _notificationService = NotificationService();
    _syncService = SyncService();
    
    // Initialize main data store with dependencies
    _dataStore = DataStore.instance;
  }

  // Getters for services
  DataStore get dataStore => _dataStore!;
  FirebaseService get firebaseService => _firebaseService!;
  NotificationService get notificationService => _notificationService!;
  SyncService get syncService => _syncService!;
  DatabaseHelper get databaseHelper => _databaseHelper!;

  /// Dispose all services
  void dispose() {
    _syncService?.dispose();
    _notificationService = null;
    _syncService = null;
    _firebaseService = null;
    _databaseHelper = null;
    _dataStore = null;
  }
}
