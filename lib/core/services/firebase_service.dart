import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:firebase_core/firebase_core.dart';
import '../models/models.dart';

class FirebaseService {
  static final FirebaseService _instance = FirebaseService._internal();
  factory FirebaseService() => _instance;
  FirebaseService._internal();

  late FirebaseFirestore _firestore;
  late firebase_auth.FirebaseAuth _auth;
  bool _initialized = false;

  Future<void> initialize() async {
    if (!_initialized) {
      await Firebase.initializeApp();
      _firestore = FirebaseFirestore.instance;
      _auth = firebase_auth.FirebaseAuth.instance;
      _initialized = true;
    }
  }

  firebase_auth.FirebaseAuth get auth => _auth;

  // User operations
  Future<void> saveUser(User user) async {
    await initialize();
    await _firestore.collection('users').doc(user.id).set({
      'email': user.email,
      'username': user.username,
      'storeName': user.storeName,
      'role': user.role.name,
      'password': user.password,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<User?> getUser(String userId) async {
    await initialize();
    final doc = await _firestore.collection('users').doc(userId).get();
    if (doc.exists) {
      final data = doc.data()!;
      return User(
        id: doc.id,
        email: data['email'],
        username: data['username'],
        storeName: data['storeName'],
        role: UserRole.values.firstWhere((e) => e.name == data['role'], orElse: () => UserRole.storeOwner),
        password: data['password'],
      );
    }
    return null;
  }

  Future<User?> getUserByUsername(String username) async {
    await initialize();
    final query = await _firestore
        .collection('users')
        .where('username', isEqualTo: username)
        .limit(1)
        .get();
    if (query.docs.isEmpty) return null;
    final doc = query.docs.first;
    final data = doc.data();
    return User(
      id: doc.id,
      email: data['email'] ?? '',
      username: data['username'] ?? '',
      storeName: data['storeName'] ?? '',
      role: UserRole.values.firstWhere(
        (e) => e.name == data['role'],
        orElse: () => UserRole.storeOwner,
      ),
      password: data['password'],
    );
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
    await _firestore.collection('users').doc(user.id).update({
      'email': user.email,
      'username': user.username,
      'storeName': user.storeName,
      'role': user.role.name,
      'password': user.password,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteUser(String userId) async {
    await initialize();
    await _firestore.collection('users').doc(userId).delete();
  }

  // Customer operations
  Future<void> saveCustomer(Customer customer) async {
    await initialize();
    await _firestore.collection('customers').doc(customer.id).set({
      'name': customer.name,
      'storeId': customer.storeId,
      'creditLimit': customer.creditLimit,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<Customer?> getCustomer(String customerId) async {
    await initialize();
    try {
      final doc = await _firestore.collection('customers').doc(customerId).get();
      if (!doc.exists) return null;
      final data = doc.data()!;
      return Customer(
        id: doc.id,
        name: data['name'],
        storeId: data['storeId'],
        creditLimit: data['creditLimit'] != null ? (data['creditLimit'] as num).toDouble() : null,
      );
    } catch (e) {
      return null;
    }
  }

  Future<List<Customer>> getAllCustomers() async {
    await initialize();
    final snapshot = await _firestore.collection('customers').get();
    return snapshot.docs.map((doc) {
      final data = doc.data();
      return Customer(
        id: doc.id,
        name: data['name'],
        storeId: data['storeId'],
        creditLimit: data['creditLimit'] != null ? (data['creditLimit'] as num).toDouble() : null,
      );
    }).toList();
  }

  Future<void> updateCustomer(Customer customer) async {
    await initialize();
    await _firestore.collection('customers').doc(customer.id).update({
      'name': customer.name,
      'storeId': customer.storeId,
      'creditLimit': customer.creditLimit,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteCustomer(String customerId) async {
    await initialize();
    await _firestore.collection('customers').doc(customerId).delete();
    
    // Delete all credits for this customer
    final creditsSnapshot = await _firestore
        .collection('credits')
        .where('customerId', isEqualTo: customerId)
        .get();
    
    for (final doc in creditsSnapshot.docs) {
      await doc.reference.delete();
    }
  }

  // Credit operations
  Future<void> saveCredit(CreditEntry credit) async {
    await initialize();
    await _firestore.collection('credits').doc(credit.id).set({
      'customerId': credit.customerId,
      'storeId': credit.storeId,
      'item': credit.item,
      'amount': credit.amount,
      'date': credit.date,
      'dueDate': credit.dueDate,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Save payments
    for (final payment in credit.payments) {
      await _firestore.collection('payments').doc(payment.id).set({
        'creditId': credit.id,
        'amount': payment.amount,
        'date': payment.date,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<CreditEntry?> getCredit(String creditId) async {
    await initialize();
    try {
      final doc = await _firestore.collection('credits').doc(creditId).get();
      if (!doc.exists) return null;
      return _creditFromSnapshot(doc);
    } catch (e) {
      return null;
    }
  }

  Future<List<CreditEntry>> getAllCredits() async {
    await initialize();
    final snapshot = await _firestore.collection('credits').get();
    List<CreditEntry> credits = [];

    for (final doc in snapshot.docs) {
      final data = doc.data();
      
      // Get payments for this credit
      final paymentsSnapshot = await _firestore
          .collection('payments')
          .where('creditId', isEqualTo: doc.id)
          .get();
      
      final payments = paymentsSnapshot.docs.map((paymentDoc) {
        final paymentData = paymentDoc.data();
        return Payment(
          id: paymentDoc.id,
          amount: paymentData['amount'],
          date: (paymentData['date'] as Timestamp).toDate(),
        );
      }).toList();

      final credit = CreditEntry(
        id: doc.id,
        customerId: data['customerId'],
        storeId: data['storeId'],
        item: data['item'],
        amount: data['amount'],
        date: (data['date'] as Timestamp).toDate(),
        dueDate: data['dueDate'] != null ? (data['dueDate'] as Timestamp).toDate() : null,
      );
      
      credit.payments.addAll(payments);
      credits.add(credit);
    }

    return credits;
  }

  Future<void> updateCredit(CreditEntry credit) async {
    await initialize();
    await _firestore.collection('credits').doc(credit.id).update({
      'customerId': credit.customerId,
      'storeId': credit.storeId,
      'item': credit.item,
      'amount': credit.amount,
      'date': credit.date,
      'dueDate': credit.dueDate,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Update payments
    await _firestore
        .collection('payments')
        .where('creditId', isEqualTo: credit.id)
        .get()
        .then((snapshot) async {
      for (final doc in snapshot.docs) {
        await doc.reference.delete();
      }
    });

    for (final payment in credit.payments) {
      await _firestore.collection('payments').doc(payment.id).set({
        'creditId': credit.id,
        'amount': payment.amount,
        'date': payment.date,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> deleteCredit(String creditId) async {
    await initialize();
    await _firestore.collection('credits').doc(creditId).delete();
    
    // Delete payments
    final paymentsSnapshot = await _firestore
        .collection('payments')
        .where('creditId', isEqualTo: creditId)
        .get();
    
    for (final doc in paymentsSnapshot.docs) {
      await doc.reference.delete();
    }
  }

  // Payment operations
  Future<Payment?> getPayment(String paymentId) async {
    await initialize();
    try {
      final doc = await _firestore.collection('payments').doc(paymentId).get();
      if (!doc.exists) return null;
      final data = doc.data()!;
      return Payment(
        id: doc.id,
        amount: data['amount'],
        date: (data['date'] as Timestamp).toDate(),
      );
    } catch (e) {
      return null;
    }
  }

  Future<void> savePayment(Payment payment, String creditId) async {
    await initialize();
    await _firestore.collection('payments').doc(payment.id).set({
      'creditId': creditId,
      'amount': payment.amount,
      'date': payment.date,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Touch parent credit so listeners receive updates
    await _firestore.collection('credits').doc(creditId).update({
      'updatedAt': FieldValue.serverTimestamp(),
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
    
    // Delete all documents in collections
    final collections = ['users', 'customers', 'credits', 'payments'];
    
    for (final collectionName in collections) {
      final snapshot = await _firestore.collection(collectionName).get();
      for (final doc in snapshot.docs) {
        await doc.reference.delete();
      }
    }
  }

  // Filtered fetch helpers
  Future<List<Customer>> getCustomersForStore(String storeId) async {
    await initialize();
    final snapshot = await _firestore
        .collection('customers')
        .where('storeId', isEqualTo: storeId)
        .get();
    return snapshot.docs.map((doc) {
      final data = doc.data();
      return Customer(
        id: doc.id,
        name: data['name'],
        storeId: data['storeId'],
        creditLimit: data['creditLimit'] != null ? (data['creditLimit'] as num).toDouble() : null,
      );
    }).toList();
  }

  Future<List<CreditEntry>> getCreditsForStore(String storeId) async {
    await initialize();
    final snapshot = await _firestore
        .collection('credits')
        .where('storeId', isEqualTo: storeId)
        .get();
    return Future.wait(snapshot.docs.map(_creditFromSnapshot));
  }

  Future<List<CreditEntry>> getCreditsForCustomer(String customerId) async {
    await initialize();
    final snapshot = await _firestore
        .collection('credits')
        .where('customerId', isEqualTo: customerId)
        .get();
    return Future.wait(snapshot.docs.map(_creditFromSnapshot));
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> listenToCreditsForCustomer(String customerId) {
    return _firestore
        .collection('credits')
        .where('customerId', isEqualTo: customerId)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> listenToCreditsForStore(String storeId) {
    return _firestore
        .collection('credits')
        .where('storeId', isEqualTo: storeId)
        .snapshots();
  }

  Future<CreditEntry> _creditFromSnapshot(DocumentSnapshot<Map<String, dynamic>> doc) async {
    final data = doc.data()!;
    final paymentsSnapshot = await _firestore
        .collection('payments')
        .where('creditId', isEqualTo: doc.id)
        .get();

    final credit = CreditEntry(
      id: doc.id,
      customerId: data['customerId'],
      storeId: data['storeId'],
      item: data['item'],
      amount: (data['amount'] as num).toDouble(),
      date: (data['date'] is Timestamp)
          ? (data['date'] as Timestamp).toDate()
          : (data['date'] as DateTime),
      dueDate: data['dueDate'] == null
          ? null
          : ((data['dueDate'] is Timestamp)
              ? (data['dueDate'] as Timestamp).toDate()
              : (data['dueDate'] as DateTime)),
    );

    final payments = paymentsSnapshot.docs.map((paymentDoc) {
      final paymentData = paymentDoc.data();
      return Payment(
        id: paymentDoc.id,
        amount: (paymentData['amount'] as num).toDouble(),
        date: (paymentData['date'] is Timestamp)
            ? (paymentData['date'] as Timestamp).toDate()
            : (paymentData['date'] as DateTime),
      );
    }).toList();

    credit.payments.addAll(payments);
    return credit;
  }
}
