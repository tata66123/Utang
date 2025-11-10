import 'dart:async';
import '../database/database_helper.dart';
import 'firebase_service.dart';
import 'connectivity_service.dart';
import '../models/models.dart';

class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  final DatabaseHelper _dbHelper = DatabaseHelper();
  final FirebaseService _firebaseService = FirebaseService();
  final ConnectivityService _connectivityService = ConnectivityService();
  
  bool _isSyncing = false;
  final StreamController<bool> _syncController = StreamController<bool>.broadcast();
  
  Stream<bool> get syncStream => _syncController.stream;
  bool get isSyncing => _isSyncing;

  Future<void> initialize() async {
    await _connectivityService.initialize();
    await _firebaseService.initialize();
    
    // Listen to connectivity changes and sync when online
    _connectivityService.connectivityStream.listen((isOnline) async {
      if (isOnline && !_isSyncing) {
        await syncNow();
      }
    });
  }

  Future<void> syncNow() async {
    if (_isSyncing) return;
    
    _isSyncing = true;
    _syncController.add(true);
    
    try {
      if (!_connectivityService.isOnline) {
        throw Exception('No internet connection');
      }

      // Get current user
      final user = await _dbHelper.getUser();
      if (user == null) {
        throw Exception('No user logged in');
      }

      // Sync user data
      await _syncUserData(user);

      // Sync customers
      await _syncCustomers();

      // Sync credits
      await _syncCredits();

      // Update sync status
      await _dbHelper.updateSyncStatus(true, lastSync: DateTime.now());

    } catch (e) {
      print('Sync error: $e');
      // Update sync status as offline
      await _dbHelper.updateSyncStatus(false);
      rethrow;
    } finally {
      _isSyncing = false;
      _syncController.add(false);
    }
  }

  Future<void> _syncUserData(User user) async {
    try {
      // Try to get user from Firebase
      final firebaseUser = await _firebaseService.getUser(user.id);
      
      if (firebaseUser == null) {
        // User doesn't exist in Firebase, create it
        await _firebaseService.saveUser(user);
      } else {
        // User exists, check if local is newer
        // For simplicity, we'll always update Firebase with local data
        await _firebaseService.updateUser(user);
      }
    } catch (e) {
      print('Error syncing user data: $e');
      rethrow;
    }
  }

  Future<void> _syncCustomers() async {
    try {
      // Step 1: Upload unsynced local customers to Firebase
      final unsyncedCustomers = await _dbHelper.getUnsyncedRecords('customers');
      
      for (final customerData in unsyncedCustomers) {
        final customer = Customer.fromJson(customerData);
        
        try {
          // Check if customer already exists in Firebase to prevent duplicates
          final firebaseCustomer = await _firebaseService.getCustomer(customer.id);
          
          if (firebaseCustomer == null) {
            // Customer doesn't exist in Firebase, create it
            await _firebaseService.saveCustomer(customer);
          } else {
            // Customer exists in Firebase, update it if local is newer
            // For now, we'll use insertOrReplace to handle updates
            await _firebaseService.updateCustomer(customer);
          }
          
          // Mark as synced only after successful upload
          await _dbHelper.markAsSynced('customers', customer.id);
        } catch (e) {
          print('Error syncing customer ${customer.id}: $e');
          // Continue with other customers - this one will retry on next sync
        }
      }

      // Step 2: Download customers from Firebase and update local database
      final firebaseCustomers = await _firebaseService.getAllCustomers();
      final localCustomers = await _dbHelper.getAllCustomers();
      final localCustomerIds = localCustomers.map((c) => c.id).toSet();
      
      for (final customer in firebaseCustomers) {
        if (!localCustomerIds.contains(customer.id)) {
          // Customer doesn't exist locally, insert it (already synced from Firebase)
          await _dbHelper.insertCustomer(customer, markAsSynced: true);
        } else {
          // Customer exists locally, check if we need to update
          // Use insertOrReplace to update if needed
          await _dbHelper.insertOrReplaceCustomer(customer);
          // Mark as synced if it wasn't already
          await _dbHelper.markAsSynced('customers', customer.id);
        }
      }
    } catch (e) {
      print('Error syncing customers: $e');
      rethrow;
    }
  }

  Future<void> _syncCredits() async {
    try {
      // Step 1: Upload unsynced local credits to Firebase
      final unsyncedCredits = await _dbHelper.getUnsyncedRecords('credits');
      final localCredits = await _dbHelper.getAllCredits();
      
      for (final creditData in unsyncedCredits) {
        // Get the credit with payments
        final credit = localCredits.firstWhere((c) => c.id == creditData['id']);
        
        try {
          // Check if credit already exists in Firebase to prevent duplicates
          final firebaseCredit = await _firebaseService.getCredit(credit.id);
          
          if (firebaseCredit == null) {
            // Credit doesn't exist in Firebase, create it
            await _firebaseService.saveCredit(credit);
          } else {
            // Credit exists in Firebase, update it
            await _firebaseService.updateCredit(credit);
          }
          
          // Mark credit as synced only after successful upload
          await _dbHelper.markAsSynced('credits', credit.id);
          
          // Also mark all payments for this credit as synced
          for (final payment in credit.payments) {
            await _dbHelper.markAsSynced('payments', payment.id);
          }
        } catch (e) {
          print('Error syncing credit ${credit.id}: $e');
          // Continue with other credits - this one will retry on next sync
        }
      }

      // Step 2: Download credits from Firebase and update local database
      final firebaseCredits = await _firebaseService.getAllCredits();
      final localCreditIds = localCredits.map((c) => c.id).toSet();
      
      for (final credit in firebaseCredits) {
        if (!localCreditIds.contains(credit.id)) {
          // Credit doesn't exist locally, insert it (already synced from Firebase)
          await _dbHelper.insertCredit(credit, markAsSynced: true);
        } else {
          // Credit exists locally, update it if needed
          // Mark it as synced after since it came from Firebase
          await _dbHelper.updateCredit(credit);
          await _dbHelper.markAsSynced('credits', credit.id);
          // Mark all payments as synced too
          for (final payment in credit.payments) {
            await _dbHelper.markAsSynced('payments', payment.id);
          }
        }
      }
      
      // Step 3: Sync standalone payments (payments added directly without credit updates)
      await _syncPayments();
    } catch (e) {
      print('Error syncing credits: $e');
      rethrow;
    }
  }

  Future<void> _syncPayments() async {
    try {
      // Get unsynced payments from local database
      final unsyncedPayments = await _dbHelper.getUnsyncedRecords('payments');
      
      for (final paymentData in unsyncedPayments) {
        final payment = Payment.fromJson(paymentData);
        final creditId = paymentData['creditId'] as String;
        
        try {
          // Check if payment already exists in Firebase to prevent duplicates
          final firebasePayment = await _firebaseService.getPayment(payment.id);
          
          if (firebasePayment == null) {
            // Payment doesn't exist in Firebase, save it
            await _firebaseService.savePayment(payment, creditId);
          }
          
          // Mark as synced only after successful upload
          await _dbHelper.markAsSynced('payments', payment.id);
        } catch (e) {
          print('Error syncing payment ${payment.id}: $e');
          // Continue with other payments - this one will retry on next sync
        }
      }
    } catch (e) {
      print('Error syncing payments: $e');
      // Don't rethrow - payment sync failure shouldn't break the entire sync
    }
  }

  Future<void> handleConflictResolution(CreditEntry localCredit, CreditEntry firebaseCredit) async {
    // Simple conflict resolution: use the most recent update
    // In a real app, you might want more sophisticated conflict resolution
    
    final localUpdated = DateTime.parse(localCredit.id); // Using ID as timestamp for simplicity
    final firebaseUpdated = DateTime.now(); // Firebase doesn't store update time in our model
    
    if (localUpdated.isAfter(firebaseUpdated)) {
      // Local is newer, update Firebase
      await _firebaseService.updateCredit(localCredit);
    } else {
      // Firebase is newer, update local
      await _dbHelper.updateCredit(firebaseCredit);
    }
  }

  Future<Map<String, dynamic>?> getSyncStatus() async {
    return await _dbHelper.getSyncStatus();
  }

  Future<void> clearAllData() async {
    await _dbHelper.clearAllData();
    await _firebaseService.clearAllData();
  }

  void dispose() {
    _connectivityService.dispose();
    _syncController.close();
  }
}
