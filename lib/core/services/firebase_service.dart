import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:firebase_core/firebase_core.dart';
import '../models/models.dart';

class FirebaseService {
  static final FirebaseService _instance = FirebaseService._internal();
  factory FirebaseService() => _instance;
  FirebaseService._internal();

  // Firebase Realtime Database URL for Asia-Southeast1 region
  static const String _databaseURL = 'https://smartcredit-35525-default-rtdb.asia-southeast1.firebasedatabase.app';

  late DatabaseReference _database;
  late firebase_auth.FirebaseAuth _auth;
  bool _initialized = false;

  Future<void> initialize() async {
    if (!_initialized) {
      await Firebase.initializeApp();
      // Use the regional database URL
      _database = FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: _databaseURL,
      ).ref();
      _auth = firebase_auth.FirebaseAuth.instance;
      _initialized = true;
    }
  }

  firebase_auth.FirebaseAuth get auth => _auth;
  DatabaseReference get database => _database;

  // Helper method to convert DateTime to timestamp
  int _toTimestamp(DateTime? date) {
    return date?.millisecondsSinceEpoch ?? 0;
  }

  // Helper method to convert timestamp to DateTime
  DateTime? _fromTimestamp(int? timestamp) {
    return timestamp != null && timestamp > 0 ? DateTime.fromMillisecondsSinceEpoch(timestamp) : null;
  }

  // User operations
  Future<void> saveUser(User user) async {
    await initialize();
    final now = DateTime.now().millisecondsSinceEpoch;
    await _database.child('users').child(user.id).set({
      'id': user.id,
      'email': user.email,
      'username': user.username,
      'storeName': user.storeName,
      'role': user.role.name,
      'password': user.password,
      'createdAt': now,
      'updatedAt': now,
    });
  }

  Future<User?> getUser(String userId) async {
    await initialize();
    try {
      final snapshot = await _database.child('users').child(userId).get();
      if (snapshot.exists && snapshot.value != null) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        return User(
          id: userId,
          email: data['email'] ?? '',
          username: data['username'] ?? '',
          storeName: data['storeName'] ?? '',
          role: UserRole.values.firstWhere((e) => e.name == data['role'], orElse: () => UserRole.storeOwner),
          password: data['password'],
        );
      }
    } catch (e) {
      print('Error getting user: $e');
    }
    return null;
  }

  Future<User?> getUserByUsername(String username) async {
    await initialize();
    try {
      final snapshot = await _database.child('users').get();
      if (snapshot.exists && snapshot.value != null) {
        final users = Map<String, dynamic>.from(snapshot.value as Map);
        for (final entry in users.entries) {
          final userData = Map<String, dynamic>.from(entry.value as Map);
          if (userData['username'] == username) {
            return User(
              id: entry.key,
              email: userData['email'] ?? '',
              username: userData['username'] ?? '',
              storeName: userData['storeName'] ?? '',
              role: UserRole.values.firstWhere(
                (e) => e.name == userData['role'],
                orElse: () => UserRole.storeOwner,
              ),
              password: userData['password'],
            );
          }
        }
      }
    } catch (e) {
      print('Error getting user by username: $e');
    }
    return null;
  }

  Future<firebase_auth.UserCredential> signInWithEmail(String email, String password) async {
    await initialize();
    return _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<void> signOut() async {
    await initialize();
    await _auth.signOut();
  }

  Future<void> updateUser(User user) async {
    await initialize();
    await _database.child('users').child(user.id).update({
      'id': user.id,
      'email': user.email,
      'username': user.username,
      'storeName': user.storeName,
      'role': user.role.name,
      'password': user.password,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> deleteUser(String userId) async {
    await initialize();
    await _database.child('users').child(userId).remove();
  }

  // Customer operations
  Future<void> saveCustomer(Customer customer) async {
    await initialize();
    final now = DateTime.now().millisecondsSinceEpoch;
    await _database.child('customers').child(customer.id).set({
      'id': customer.id,
      'name': customer.name,
      'storeId': customer.storeId,
      'creditLimit': customer.creditLimit,
      'createdAt': now,
      'updatedAt': now,
    });
  }

  Future<Customer?> getCustomer(String customerId) async {
    await initialize();
    try {
      final snapshot = await _database.child('customers').child(customerId).get();
      if (snapshot.exists && snapshot.value != null) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        return Customer(
          id: customerId,
          name: data['name'] ?? '',
          storeId: data['storeId'],
          creditLimit: data['creditLimit'] != null ? (data['creditLimit'] as num).toDouble() : null,
        );
      }
    } catch (e) {
      print('Error getting customer: $e');
    }
    return null;
  }

  Future<List<Customer>> getAllCustomers() async {
    await initialize();
    try {
      final snapshot = await _database.child('customers').get();
      if (snapshot.exists && snapshot.value != null) {
        final customers = Map<String, dynamic>.from(snapshot.value as Map);
        return customers.entries.map((entry) {
          final data = Map<String, dynamic>.from(entry.value as Map);
          return Customer(
            id: entry.key,
            name: data['name'] ?? '',
            storeId: data['storeId'],
            creditLimit: data['creditLimit'] != null ? (data['creditLimit'] as num).toDouble() : null,
          );
        }).toList();
      }
    } catch (e) {
      print('Error getting all customers: $e');
    }
    return [];
  }

  Future<void> updateCustomer(Customer customer) async {
    await initialize();
    await _database.child('customers').child(customer.id).update({
      'id': customer.id,
      'name': customer.name,
      'storeId': customer.storeId,
      'creditLimit': customer.creditLimit,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> deleteCustomer(String customerId) async {
    await initialize();
    await _database.child('customers').child(customerId).remove();
    
    // Delete all credits for this customer
    try {
      final creditsSnapshot = await _database.child('credits').get();
      if (creditsSnapshot.exists && creditsSnapshot.value != null) {
        final credits = Map<String, dynamic>.from(creditsSnapshot.value as Map);
        for (final entry in credits.entries) {
          final creditData = Map<String, dynamic>.from(entry.value as Map);
          if (creditData['customerId'] == customerId) {
            await _database.child('credits').child(entry.key).remove();
            // Also delete payments for this credit
            final payments = await _getPaymentsForCredit(entry.key);
            for (final payment in payments) {
              await _database.child('payments').child(payment.id).remove();
            }
          }
        }
      }
    } catch (e) {
      print('Error deleting customer credits: $e');
    }
  }

  // Credit operations
  Future<void> saveCredit(CreditEntry credit) async {
    await initialize();
    final now = DateTime.now().millisecondsSinceEpoch;
    await _database.child('credits').child(credit.id).set({
      'id': credit.id,
      'customerId': credit.customerId,
      'storeId': credit.storeId,
      'item': credit.item,
      'amount': credit.amount,
      'date': _toTimestamp(credit.date),
      'dueDate': _toTimestamp(credit.dueDate),
      'createdAt': now,
      'updatedAt': now,
    });

    // Save payments
    for (final payment in credit.payments) {
      await _database.child('payments').child(payment.id).set({
        'id': payment.id,
        'creditId': credit.id,
        'amount': payment.amount,
        'date': _toTimestamp(payment.date),
        'createdAt': now,
        'updatedAt': now,
      });
    }
  }

  // Helper method to get payments for a credit (avoids index requirement)
  Future<List<Payment>> _getPaymentsForCredit(String creditId) async {
    final allPaymentsSnapshot = await _database.child('payments').get();
    final List<Payment> payments = [];
    if (allPaymentsSnapshot.exists && allPaymentsSnapshot.value != null) {
      final allPayments = Map<String, dynamic>.from(allPaymentsSnapshot.value as Map);
      for (final entry in allPayments.entries) {
        final paymentData = Map<String, dynamic>.from(entry.value as Map);
        if (paymentData['creditId'] == creditId) {
          payments.add(Payment(
            id: entry.key,
            amount: (paymentData['amount'] as num).toDouble(),
            date: _fromTimestamp(paymentData['date'] as int?) ?? DateTime.now(),
          ));
        }
      }
    }
    return payments;
  }

  Future<CreditEntry?> getCredit(String creditId) async {
    await initialize();
    try {
      final snapshot = await _database.child('credits').child(creditId).get();
      if (snapshot.exists && snapshot.value != null) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        
        // Get payments for this credit
        final payments = await _getPaymentsForCredit(creditId);

        final credit = CreditEntry(
          id: creditId,
          customerId: data['customerId'] ?? '',
          storeId: data['storeId'],
          item: data['item'] ?? '',
          amount: (data['amount'] as num).toDouble(),
          date: _fromTimestamp(data['date'] as int?) ?? DateTime.now(),
          dueDate: _fromTimestamp(data['dueDate'] as int?),
        );
        
        credit.payments.addAll(payments);
        return credit;
      }
    } catch (e) {
      print('Error getting credit: $e');
    }
    return null;
  }

  Future<List<CreditEntry>> getAllCredits() async {
    await initialize();
    try {
      final snapshot = await _database.child('credits').get();
      if (snapshot.exists && snapshot.value != null) {
        final credits = Map<String, dynamic>.from(snapshot.value as Map);
        List<CreditEntry> creditList = [];

        // Fetch all payments once to avoid multiple queries
        final allPaymentsSnapshot = await _database.child('payments').get();
        final Map<String, List<Payment>> paymentsByCreditId = {};
        if (allPaymentsSnapshot.exists && allPaymentsSnapshot.value != null) {
          final allPayments = Map<String, dynamic>.from(allPaymentsSnapshot.value as Map);
          for (final paymentEntry in allPayments.entries) {
            final paymentData = Map<String, dynamic>.from(paymentEntry.value as Map);
            final paymentCreditId = paymentData['creditId'] as String?;
            if (paymentCreditId != null) {
              paymentsByCreditId.putIfAbsent(paymentCreditId, () => []).add(
                Payment(
                  id: paymentEntry.key,
                  amount: (paymentData['amount'] as num).toDouble(),
                  date: _fromTimestamp(paymentData['date'] as int?) ?? DateTime.now(),
                )
              );
            }
          }
        }

        for (final entry in credits.entries) {
          final data = Map<String, dynamic>.from(entry.value as Map);
          
          // Get payments for this credit from the pre-fetched map
          final payments = paymentsByCreditId[entry.key] ?? [];

          final credit = CreditEntry(
            id: entry.key,
            customerId: data['customerId'] ?? '',
            storeId: data['storeId'],
            item: data['item'] ?? '',
            amount: (data['amount'] as num).toDouble(),
            date: _fromTimestamp(data['date'] as int?) ?? DateTime.now(),
            dueDate: _fromTimestamp(data['dueDate'] as int?),
          );
          
          credit.payments.addAll(payments);
          creditList.add(credit);
        }

        return creditList;
      }
    } catch (e) {
      print('Error getting all credits: $e');
    }
    return [];
  }

  Future<void> updateCredit(CreditEntry credit) async {
    await initialize();
    await _database.child('credits').child(credit.id).update({
      'id': credit.id,
      'customerId': credit.customerId,
      'storeId': credit.storeId,
      'item': credit.item,
      'amount': credit.amount,
      'date': _toTimestamp(credit.date),
      'dueDate': _toTimestamp(credit.dueDate),
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    });

    // Delete existing payments and add new ones
    try {
      final payments = await _getPaymentsForCredit(credit.id);
      for (final payment in payments) {
        await _database.child('payments').child(payment.id).remove();
      }
    } catch (e) {
      print('Error deleting old payments: $e');
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    for (final payment in credit.payments) {
      await _database.child('payments').child(payment.id).set({
        'id': payment.id,
        'creditId': credit.id,
        'amount': payment.amount,
        'date': _toTimestamp(payment.date),
        'createdAt': now,
        'updatedAt': now,
      });
    }
  }

  Future<void> deleteCredit(String creditId) async {
    await initialize();
    await _database.child('credits').child(creditId).remove();
    
    // Delete payments
    try {
      final payments = await _getPaymentsForCredit(creditId);
      for (final payment in payments) {
        await _database.child('payments').child(payment.id).remove();
      }
    } catch (e) {
      print('Error deleting payments: $e');
    }
  }

  // Payment operations
  Future<Payment?> getPayment(String paymentId) async {
    await initialize();
    try {
      final snapshot = await _database.child('payments').child(paymentId).get();
      if (snapshot.exists && snapshot.value != null) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        return Payment(
          id: paymentId,
          amount: (data['amount'] as num).toDouble(),
          date: _fromTimestamp(data['date'] as int?) ?? DateTime.now(),
        );
      }
    } catch (e) {
      print('Error getting payment: $e');
    }
    return null;
  }

  Future<void> savePayment(Payment payment, String creditId) async {
    await initialize();
    final now = DateTime.now().millisecondsSinceEpoch;
    await _database.child('payments').child(payment.id).set({
      'id': payment.id,
      'creditId': creditId,
      'amount': payment.amount,
      'date': _toTimestamp(payment.date),
      'createdAt': now,
      'updatedAt': now,
    });

    // Touch parent credit so listeners receive updates
    await _database.child('credits').child(creditId).update({
      'updatedAt': now,
    });
  }

  // Sync operations
  Future<void> syncData(List<Customer> customers, List<CreditEntry> credits) async {
    await initialize();
    
    // Sync customers
    for (final customer in customers) {
      await saveCustomer(customer);
    }
    
    // Sync credits
    for (final credit in credits) {
      await saveCredit(credit);
    }
  }

  Future<void> clearAllData() async {
    await initialize();
    
    // Delete all data in Realtime Database
    await _database.child('users').remove();
    await _database.child('customers').remove();
    await _database.child('credits').remove();
    await _database.child('payments').remove();
    await _database.child('notifications').remove();
  }

  // Filtered fetch helpers
  Future<List<Customer>> getCustomersForStore(String storeId) async {
    await initialize();
    try {
      final snapshot = await _database.child('customers').get();
      if (snapshot.exists && snapshot.value != null) {
        final customers = Map<String, dynamic>.from(snapshot.value as Map);
        return customers.entries
            .where((entry) {
              final data = Map<String, dynamic>.from(entry.value as Map);
              return data['storeId'] == storeId;
            })
            .map((entry) {
              final data = Map<String, dynamic>.from(entry.value as Map);
              return Customer(
                id: entry.key,
                name: data['name'] ?? '',
                storeId: data['storeId'],
                creditLimit: data['creditLimit'] != null ? (data['creditLimit'] as num).toDouble() : null,
              );
            })
            .toList();
      }
    } catch (e) {
      print('Error getting customers for store: $e');
    }
    return [];
  }

  Future<List<CreditEntry>> getCreditsForStore(String storeId) async {
    await initialize();
    try {
      final snapshot = await _database.child('credits').get();
      if (snapshot.exists && snapshot.value != null) {
        final credits = Map<String, dynamic>.from(snapshot.value as Map);
        List<CreditEntry> creditList = [];

        // Fetch all payments once to avoid multiple queries
        final allPaymentsSnapshot = await _database.child('payments').get();
        final Map<String, List<Payment>> paymentsByCreditId = {};
        if (allPaymentsSnapshot.exists && allPaymentsSnapshot.value != null) {
          final allPayments = Map<String, dynamic>.from(allPaymentsSnapshot.value as Map);
          for (final paymentEntry in allPayments.entries) {
            final paymentData = Map<String, dynamic>.from(paymentEntry.value as Map);
            final paymentCreditId = paymentData['creditId'] as String?;
            if (paymentCreditId != null) {
              paymentsByCreditId.putIfAbsent(paymentCreditId, () => []).add(
                Payment(
                  id: paymentEntry.key,
                  amount: (paymentData['amount'] as num).toDouble(),
                  date: _fromTimestamp(paymentData['date'] as int?) ?? DateTime.now(),
                )
              );
            }
          }
        }

        for (final entry in credits.entries) {
          final data = Map<String, dynamic>.from(entry.value as Map);
          if (data['storeId'] == storeId) {
            // Get payments for this credit from the pre-fetched map
            final payments = paymentsByCreditId[entry.key] ?? [];

            final credit = CreditEntry(
              id: entry.key,
              customerId: data['customerId'] ?? '',
              storeId: data['storeId'],
              item: data['item'] ?? '',
              amount: (data['amount'] as num).toDouble(),
              date: _fromTimestamp(data['date'] as int?) ?? DateTime.now(),
              dueDate: _fromTimestamp(data['dueDate'] as int?),
            );
            
            credit.payments.addAll(payments);
            creditList.add(credit);
          }
        }

        return creditList;
      }
    } catch (e) {
      print('Error getting credits for store: $e');
    }
    return [];
  }

  Future<List<CreditEntry>> getCreditsForCustomer(String customerId) async {
    await initialize();
    try {
      final snapshot = await _database.child('credits').get();
      if (snapshot.exists && snapshot.value != null) {
        final credits = Map<String, dynamic>.from(snapshot.value as Map);
        List<CreditEntry> creditList = [];

        // Fetch all payments once (avoiding orderByChild query that requires index)
        final allPaymentsSnapshot = await _database.child('payments').get();
        final Map<String, List<Payment>> paymentsByCreditId = {};
        
        if (allPaymentsSnapshot.exists && allPaymentsSnapshot.value != null) {
          final allPayments = Map<String, dynamic>.from(allPaymentsSnapshot.value as Map);
          for (final paymentEntry in allPayments.entries) {
            final paymentData = Map<String, dynamic>.from(paymentEntry.value as Map);
            final paymentCreditId = paymentData['creditId'] as String?;
            if (paymentCreditId != null) {
              paymentsByCreditId.putIfAbsent(paymentCreditId, () => []).add(
                Payment(
                  id: paymentEntry.key,
                  amount: (paymentData['amount'] as num).toDouble(),
                  date: _fromTimestamp(paymentData['date'] as int?) ?? DateTime.now(),
                )
              );
            }
          }
        }

        for (final entry in credits.entries) {
          final data = Map<String, dynamic>.from(entry.value as Map);
          if (data['customerId'] == customerId) {
            final credit = CreditEntry(
              id: entry.key,
              customerId: data['customerId'] ?? '',
              storeId: data['storeId'],
              item: data['item'] ?? '',
              amount: (data['amount'] as num).toDouble(),
              date: _fromTimestamp(data['date'] as int?) ?? DateTime.now(),
              dueDate: _fromTimestamp(data['dueDate'] as int?),
            );
            
            // Add payments for this credit
            credit.payments.addAll(paymentsByCreditId[entry.key] ?? []);
            creditList.add(credit);
          }
        }

        return creditList;
      }
    } catch (e) {
      print('Error getting credits for customer: $e');
    }
    return [];
  }

  // Realtime Database listeners (replacing Firestore streams)
  Stream<DatabaseEvent> listenToCreditsForCustomer(String customerId) {
    return _database.child('credits').orderByChild('customerId').equalTo(customerId).onValue;
  }

  Stream<DatabaseEvent> listenToCreditsForStore(String storeId) {
    return _database.child('credits').orderByChild('storeId').equalTo(storeId).onValue;
  }

  // Listen to customers for a specific store
  Stream<DatabaseEvent> listenToCustomersForStore(String storeId) {
    return _database.child('customers').orderByChild('storeId').equalTo(storeId).onValue;
  }

  // Listen to all customers (for store owners who need to see all customers)
  Stream<DatabaseEvent> listenToAllCustomers() {
    return _database.child('customers').onValue;
  }

  // Notification operations for cross-device notifications
  Future<void> saveNotification({
    required String userId,
    required String title,
    required String message,
    required String type,
    Map<String, dynamic>? data,
  }) async {
    await initialize();
    final notificationId = DateTime.now().millisecondsSinceEpoch.toString();
    await _database.child('notifications').child(userId).child(notificationId).set({
      'title': title,
      'message': message,
      'type': type,
      'data': data,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
      'read': false,
    });
  }

  Stream<DatabaseEvent> listenToNotifications(String userId) {
    return _database.child('notifications').child(userId).orderByChild('createdAt').onValue;
  }

  Future<void> markNotificationAsRead(String userId, String notificationId) async {
    await initialize();
    await _database.child('notifications').child(userId).child(notificationId).update({
      'read': true,
    });
  }
}
