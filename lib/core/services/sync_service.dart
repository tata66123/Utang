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
      // Check if user already exists in Firebase
      final firebaseUser = await _firebaseService.getUser(user.id);
      
      if (firebaseUser == null) {
        // User doesn't exist in Firebase, upload it (offline-created)
        print('Uploading offline-created user: ${user.username} (${user.id})');
        await _firebaseService.saveUser(user);
      } else {
        // User already exists in Firebase, skip to avoid duplicates
        print('User ${user.username} (${user.id}) already exists in Firebase, skipping');
      }
    } catch (e) {
      print('Error syncing user data: $e');
      rethrow;
    }
  }

  Future<void> _syncCustomers() async {
    try {
      // Only upload unsynced local customers to Firebase (offline-created data)
      final unsyncedCustomers = await _dbHelper.getUnsyncedRecords('customers');
      
      print('Found ${unsyncedCustomers.length} unsynced customers to upload');
      
      for (final customerData in unsyncedCustomers) {
        final customer = Customer.fromJson(customerData);
        
        try {
          // Check if customer already exists in Firebase to prevent duplicates
          final firebaseCustomer = await _firebaseService.getCustomer(customer.id);
          
          if (firebaseCustomer == null) {
            // Customer doesn't exist in Firebase, upload it (offline-created)
            print('Uploading offline-created customer: ${customer.name} (${customer.id})');
            await _firebaseService.saveCustomer(customer);
            // Mark as synced only after successful upload
            await _dbHelper.markAsSynced('customers', customer.id);
          } else {
            // Customer already exists in Firebase, skip to avoid duplicates
            print('Customer ${customer.name} (${customer.id}) already exists in Firebase, skipping');
            // Mark as synced since it already exists in Firebase
            await _dbHelper.markAsSynced('customers', customer.id);
          }
        } catch (e) {
          print('Error syncing customer ${customer.id}: $e');
          // Continue with other customers - this one will retry on next sync
        }
      }
      
      // Do NOT download from Firebase - only upload offline-created data
      print('Customer sync completed. Only uploaded offline-created customers.');
    } catch (e) {
      print('Error syncing customers: $e');
      rethrow;
    }
  }

  Future<void> _syncCredits() async {
    try {
      // Only upload unsynced local credits to Firebase (offline-created data)
      final unsyncedCredits = await _dbHelper.getUnsyncedRecords('credits');
      final localCredits = await _dbHelper.getAllCredits();
      
      print('Found ${unsyncedCredits.length} unsynced credits to upload');
      
      for (final creditData in unsyncedCredits) {
        // Get the credit with payments
        final credit = localCredits.firstWhere((c) => c.id == creditData['id']);
        
        try {
          // Check if credit already exists in Firebase to prevent duplicates
          final firebaseCredit = await _firebaseService.getCredit(credit.id);
          
          if (firebaseCredit == null) {
            // Credit doesn't exist in Firebase, upload it (offline-created)
            print('Uploading offline-created credit: ${credit.item} (${credit.id})');
            await _firebaseService.saveCredit(credit);
            // Mark credit as synced only after successful upload
            await _dbHelper.markAsSynced('credits', credit.id);
            
            // Also mark all payments for this credit as synced
            for (final payment in credit.payments) {
              await _dbHelper.markAsSynced('payments', payment.id);
            }
            
            // CRITICAL: Send notification to customer when offline-created credit is synced
            if (credit.storeId != null && credit.customerId.isNotEmpty) {
              try {
                final customer = await _dbHelper.getCustomerById(credit.customerId);
                if (customer != null) {
                  // Get store owner info
                  var storeOwner = await _dbHelper.getUserById(credit.storeId!);
                  if (storeOwner == null) {
                    storeOwner = await _firebaseService.getUser(credit.storeId!);
                    if (storeOwner != null) {
                      await _dbHelper.insertOrReplaceUser(storeOwner);
                    }
                  }
                  
                  final storeName = storeOwner?.storeName ?? 'Store';
                  
                  await _firebaseService.saveNotification(
                    userId: credit.customerId,
                    title: 'New Credit Added',
                    message: '₱${credit.amount.toStringAsFixed(2)} credit added for ${credit.item}',
                    type: 'credit_added',
                    data: {
                      'creditId': credit.id,
                      'storeId': credit.storeId,
                      'storeName': storeName,
                      'amount': credit.amount,
                      'item': credit.item,
                    },
                  );
                  print('Credit notification sent to customer ${credit.customerId} after offline sync');
                }
              } catch (e) {
                print('Error sending credit notification after sync: $e');
                // Don't fail sync if notification fails
              }
            }
          } else {
            // Credit exists in Firebase - update it with the latest local changes (including new payments)
            print('Credit ${credit.item} (${credit.id}) already exists in Firebase, updating with local changes');

            // Gather unsynced payments for this credit before updating Firebase
            final unsyncedPaymentMaps = await _dbHelper.getUnsyncedRecords('payments');
            final List<Map<String, dynamic>> creditUnsyncedPaymentMaps = unsyncedPaymentMaps
                .where((payment) => payment['creditId'] == credit.id)
                .toList();
            final List<Payment> creditUnsyncedPayments = creditUnsyncedPaymentMaps
                .map((map) => Payment.fromJson(map))
                .toList();

            // Push the latest credit (and its payments) to Firebase
            await _firebaseService.updateCredit(credit);

            // Mark credit as synced after successful update
            await _dbHelper.markAsSynced('credits', credit.id);

            // Mark the payments we just uploaded as synced
            for (final paymentMap in creditUnsyncedPaymentMaps) {
              final paymentId = paymentMap['id'] as String?;
              if (paymentId != null) {
                await _dbHelper.markAsSynced('payments', paymentId);
              }
            }

            // Notify the customer about newly synced payments
            if (creditUnsyncedPayments.isNotEmpty) {
              try {
                final customer = await _dbHelper.getCustomerById(credit.customerId);
                if (customer != null && credit.storeId != null && credit.storeId!.isNotEmpty) {
                  // Ensure we know the store owner's name (fallback to Firebase if missing locally)
                  var storeOwner = await _dbHelper.getUserById(credit.storeId!);
                  if (storeOwner == null) {
                    storeOwner = await _firebaseService.getUser(credit.storeId!);
                    if (storeOwner != null) {
                      await _dbHelper.insertOrReplaceUser(storeOwner);
                    }
                  }

                  final storeName = storeOwner?.storeName ?? 'Store';
                  final totalNewPayment = creditUnsyncedPayments.fold(0.0, (sum, payment) => sum + payment.amount);

                  await _firebaseService.saveNotification(
                    userId: credit.customerId,
                    title: 'Payment Recorded',
                    message: '₱${totalNewPayment.toStringAsFixed(2)} payment recorded for ${credit.item}',
                    type: 'payment_received',
                    data: {
                      'creditId': credit.id,
                      'storeId': credit.storeId,
                      'storeName': storeName,
                      'amount': totalNewPayment,
                      'item': credit.item,
                      'balance': credit.balance,
                    },
                  );

                  print('Payment notification sent to customer ${credit.customerId} for ${creditUnsyncedPayments.length} new payment(s)');
                }
              } catch (e) {
                print('Error sending payment notification after credit update: $e');
              }
            }
          }
        } catch (e) {
          print('Error syncing credit ${credit.id}: $e');
          // Continue with other credits - this one will retry on next sync
        }
      }
      
      // Sync standalone payments (payments added directly without credit updates)
      await _syncPayments();
      
      // Do NOT download from Firebase - only upload offline-created data
      print('Credit sync completed. Only uploaded offline-created credits.');
    } catch (e) {
      print('Error syncing credits: $e');
      rethrow;
    }
  }

  Future<void> _syncPayments() async {
    try {
      // Only upload unsynced payments to Firebase (offline-created data)
      final unsyncedPayments = await _dbHelper.getUnsyncedRecords('payments');
      
      print('Found ${unsyncedPayments.length} unsynced payments to upload');
      
      // Track which credits need to be updated and which payments were just synced
      final Set<String> creditsToUpdate = {};
      final Map<String, List<Payment>> newlySyncedPayments = {}; // creditId -> list of newly synced payments
      
      for (final paymentData in unsyncedPayments) {
        final payment = Payment.fromJson(paymentData);
        final creditId = paymentData['creditId'] as String;
        
        try {
          // Check if payment already exists in Firebase to prevent duplicates
          final firebasePayment = await _firebaseService.getPayment(payment.id);
          
          if (firebasePayment == null) {
            // Payment doesn't exist in Firebase, upload it (offline-created)
            print('Uploading offline-created payment: ${payment.id} for credit $creditId');
            await _firebaseService.savePayment(payment, creditId);
            // Mark as synced only after successful upload
            await _dbHelper.markAsSynced('payments', payment.id);
            // Track that this credit needs to be updated
            creditsToUpdate.add(creditId);
            // Track this payment as newly synced
            newlySyncedPayments.putIfAbsent(creditId, () => []).add(payment);
          } else {
            // Payment already exists in Firebase, skip to avoid duplicates
            print('Payment ${payment.id} already exists in Firebase, skipping');
            // Mark as synced since it already exists in Firebase
            await _dbHelper.markAsSynced('payments', payment.id);
          }
        } catch (e) {
          print('Error syncing payment ${payment.id}: $e');
          // Continue with other payments - this one will retry on next sync
        }
      }
      
      // Update parent credit entries in Firebase to reflect the new payments
      // This ensures customers see the updated balance
      if (creditsToUpdate.isNotEmpty) {
        print('Updating ${creditsToUpdate.length} credit entries in Firebase to reflect new payments');
        final localCredits = await _dbHelper.getAllCredits();
        
        // Get all unsynced payments once to avoid multiple queries
        final allUnsyncedPayments = await _dbHelper.getUnsyncedRecords('payments');
        final unsyncedPaymentIds = allUnsyncedPayments.map((p) => p['id'] as String).toSet();
        
        for (final creditId in creditsToUpdate) {
          try {
            // Find the credit in local database (with all payments)
            final credit = localCredits.firstWhere(
              (c) => c.id == creditId,
              orElse: () => throw StateError('Credit $creditId not found in local database'),
            );
            
            // Sync any remaining unsynced payments for this credit first
            for (final payment in credit.payments) {
              if (unsyncedPaymentIds.contains(payment.id)) {
                print('Syncing payment ${payment.id} for credit $creditId');
                await _firebaseService.savePayment(payment, creditId);
                await _dbHelper.markAsSynced('payments', payment.id);
              }
            }
            
            // Update the credit in Firebase with all payments
            // This ensures the credit entry reflects the correct balance
            print('Updating credit ${credit.id} in Firebase with ${credit.payments.length} payment(s)');
            await _firebaseService.updateCredit(credit);
            
            // Send notification to customer about the newly synced payments
            // This ensures customers receive updates when payments are synced from offline mode
            try {
              final newlySynced = newlySyncedPayments[creditId] ?? [];
              if (newlySynced.isNotEmpty) {
                final customer = await _dbHelper.getCustomerById(credit.customerId);
                if (customer != null && credit.storeId != null) {
                  // Get store owner info for notification
                  final storeOwner = await _dbHelper.getUserById(credit.storeId!);
                  final storeName = storeOwner?.storeName ?? 'Store';
                  
                  // Calculate total amount of newly synced payments
                  final totalNewPayment = newlySynced.fold(0.0, (sum, p) => sum + p.amount);
                  
                  // Send notification to customer
                  await _firebaseService.saveNotification(
                    userId: credit.customerId,
                    title: 'Payment Recorded',
                    message: '₱${totalNewPayment.toStringAsFixed(2)} payment recorded for ${credit.item}',
                    type: 'payment_received',
                    data: {
                      'creditId': credit.id,
                      'storeId': credit.storeId,
                      'storeName': storeName,
                      'amount': totalNewPayment,
                      'item': credit.item,
                      'balance': credit.balance,
                    },
                  );
                  print('Payment notification sent to customer ${credit.customerId} for ${newlySynced.length} payment(s)');
                }
              }
            } catch (e) {
              print('Error sending payment notification: $e');
              // Don't fail the sync if notification fails
            }
          } catch (e) {
            print('Error updating credit $creditId in Firebase: $e');
            // Continue with other credits
          }
        }
      }
      
      // Do NOT download from Firebase - only upload offline-created data
      print('Payment sync completed. Only uploaded offline-created payments.');
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
