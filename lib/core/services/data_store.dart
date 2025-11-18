import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../database/database_helper.dart';
import '../interfaces/service_interface.dart';
import '../factories/user_factory.dart';
import 'sync_service.dart';
import 'firebase_service.dart';
import 'connectivity_service.dart';
import 'notification_service.dart';

class DataStore extends ChangeNotifier implements AuthServiceInterface {
  DataStore._();
  static final DataStore instance = DataStore._();

  static const String _themeKey = 'app_theme_mode';
  AppState _state = AppState(customers: <Customer>[], credits: <CreditEntry>[], currentUser: null);
  bool _isDarkMode = false;
  bool _isSyncing = false;

  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();
  final FirebaseService _firebaseService = FirebaseService();
  final ConnectivityService _connectivityService = ConnectivityService();
  final NotificationService _notificationService = NotificationService();
  StreamSubscription<DatabaseEvent>? _creditSubscription;
  StreamSubscription<DatabaseEvent>? _customerSubscription;
  StreamSubscription<DatabaseEvent>? _paymentSubscription;
  StreamSubscription<DatabaseEvent>? _notificationSubscription;
  StreamSubscription<DatabaseEvent>? _userSubscription;

  // AuthServiceInterface implementation
  @override
  User? getCurrentUser() => _state.currentUser;

  @override
  bool get isLoggedIn => _state.currentUser != null;

  @override
  Future<User> registerUser({
    required String email,
    required String username,
    required String storeName,
    required String password,
    required UserRole role,
  }) async {
    return addUser(
      email: email,
      username: username,
      storeName: storeName,
      password: password,
      role: role,
    );
  }

  AppState get state => _state;
  bool get isDarkMode => _isDarkMode;
  bool get isSyncing => _isSyncing;

  Future<void> load() async {
    try {
      // Initialize services
      await _connectivityService.initialize();
      await _syncService.initialize();
      await _firebaseService.initialize();
      
      // IMPORTANT: When online, ONLY use Firebase, ignore SQLite for login
      // SQLite is ONLY for offline mode
      User? user;
      
      if (_connectivityService.isOnline) {
        // Online: Don't auto-login from SQLite, require explicit login
        // This prevents logging into deleted accounts
        user = null;
      } else {
        // Offline: Use SQLite as fallback
        user = await _dbHelper.getUser();
        if (user != null) {
          await _clearOtherUsersData(user);
        }
      }
      
      await _setStateFromDatabase(user);

      // Load theme preference
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      _isDarkMode = prefs.getBool(_themeKey) ?? false;
      
      notifyListeners();
      
      if (user != null) {
        await _startRealtimeSyncForCurrentUser();
        
        // Try to sync in background if online
        if (_connectivityService.isOnline && !_isSyncing) {
          _syncInBackground();
        }
      }
    } catch (e) {
      print('Error loading data: $e');
      // Initialize with empty state if error occurs
      _state = AppState(customers: <Customer>[], credits: <CreditEntry>[], currentUser: null);
      notifyListeners();
    }
  }

  Future<void> _syncInBackground() async {
    try {
      await _syncService.syncNow();
    } catch (e) {
      print('Background sync failed: $e');
    }
  }

  Future<User> addUser({required String email, required String username, required String storeName, required String password, required UserRole role}) async {
    final User user = UserFactory.createUser(
      id: generateId(),
      email: email.trim(),
      username: username.trim(),
      name: storeName.trim(),
      password: password,
      role: role,
    );
    
    await _dbHelper.insertUser(user);
    
    // IMPORTANT: Clear data from other users when creating a new account
    // This ensures each new account starts with a blank slate
    await _clearOtherUsersData(user);
    
    // Immediately sync user to Firebase
    await _syncUserToFirebase(user);
    
    // If this is a customer, also create a corresponding Customer record
    if (role == UserRole.customer) {
      // Check if there's already a customer record with this username
      final existingCustomer = findCustomerByUsername(username.trim());
      
      if (existingCustomer != null) {
        // Update the existing customer record to use the user's ID
        final updatedCustomer = Customer(id: user.id, name: username.trim(), storeId: null);
        await _dbHelper.updateCustomer(updatedCustomer);
        
        // Immediately sync updated customer to Firebase
        await _syncCustomerToFirebase(updatedCustomer);
        
        // Update all credits for this customer to use the new ID
        for (final credit in _state.credits.where((c) => c.customerId == existingCustomer.id)) {
          final updatedCredit = CreditEntry(
            id: credit.id,
            customerId: user.id,
            item: credit.item,
            amount: credit.amount,
            date: credit.date,
            dueDate: credit.dueDate,
          );
          updatedCredit.payments.addAll(credit.payments);
          await _dbHelper.updateCredit(updatedCredit);
        }
        
        // Update the state
        final customerIndex = _state.customers.indexWhere((c) => c.id == existingCustomer.id);
        if (customerIndex != -1) {
          _state.customers[customerIndex] = updatedCustomer;
        }
        
        // Update credits in state
        for (int i = 0; i < _state.credits.length; i++) {
          if (_state.credits[i].customerId == existingCustomer.id) {
            final oldCredit = _state.credits[i];
            _state.credits[i] = CreditEntry(
              id: oldCredit.id,
              customerId: user.id,
              item: oldCredit.item,
              amount: oldCredit.amount,
              date: oldCredit.date,
              dueDate: oldCredit.dueDate,
            );
            _state.credits[i].payments.addAll(oldCredit.payments);
          }
        }
      } else {
        // Create new customer record
        final Customer customer = Customer(id: user.id, name: username.trim(), storeId: null);
        await _dbHelper.insertOrReplaceCustomer(customer);
        
        // Immediately sync customer to Firebase so store owners can see it
        await _syncCustomerToFirebase(customer);
        
        _state.customers.add(customer);
      }
    }
    
    _state = AppState(
      customers: _state.customers, 
      credits: _state.credits, 
      currentUser: user
    );
    notifyListeners();
    await _startRealtimeSyncForCurrentUser();
    return user;
  }

  @override
  Future<bool> loginUser(String username, String password) async {
    try {
      await _connectivityService.initialize();
      
      // IMPORTANT: When online, ONLY use Firebase (ignore SQLite)
      // SQLite is ONLY for offline mode
      if (_connectivityService.isOnline) {
        // Online: Use Firebase ONLY
        await _firebaseService.initialize();
        final remoteUser = await _firebaseService.getUserByUsername(username);
        if (remoteUser == null) {
          return false;
        }

        // Validate password either via Firebase Auth or stored password
        bool credentialsValid = false;

        if (remoteUser.email.isNotEmpty) {
          try {
            await _firebaseService.signInWithEmail(remoteUser.email, password);
            credentialsValid = true;
          } catch (e) {
            print('Firebase auth sign-in failed: $e');
          }
        }

        if (!credentialsValid) {
          final storedPassword = remoteUser.password;
          if (storedPassword == null || storedPassword == password) {
            credentialsValid = true;
          }
        }

        if (!credentialsValid) {
          return false;
        }

        // IMPORTANT: Clear ALL SQLite data before logging in (prevent old data)
        await _dbHelper.clearAllData();
        
        // Save user to SQLite for offline use
        await _dbHelper.insertOrReplaceUser(remoteUser);
        
        // IMPORTANT: Clear data from other users before downloading
        await _clearOtherUsersData(remoteUser);
        
        await _downloadAndCacheUserData(remoteUser);
        await _setStateFromDatabase(remoteUser);
        await _startRealtimeSyncForCurrentUser();
        return true;
      } else {
        // Offline: Use SQLite as fallback
        final localUser = await _dbHelper.getUserByUsername(username);
        if (localUser != null && (localUser.password == null || localUser.password == password)) {
        // IMPORTANT: Clear data from other users before loading
        await _clearOtherUsersData(localUser);
        await _setStateFromDatabase(localUser);
        await _startRealtimeSyncForCurrentUser();
        return true;
        }
        return false;
      }
    } catch (e) {
      print('Login error: $e');
      return false;
    }
  }

  // Clear data that doesn't belong to the current user
  Future<void> _clearOtherUsersData(User user) async {
    try {
      if (user.role == UserRole.storeOwner) {
        // For store owners: clear customers and credits from other stores
        await _dbHelper.clearDataForOtherStores(user.id);
        print('Cleared data for other stores. Current store: ${user.id}');
      } else {
        // For customers: clear data from other customers
        await _dbHelper.clearDataForOtherCustomers(user.id);
        print('Cleared data for other customers. Current customer: ${user.id}');
      }
      
      // Also clear the in-memory state to ensure clean slate
      _state = AppState(
        customers: <Customer>[],
        credits: <CreditEntry>[],
        currentUser: user,
      );
    } catch (e) {
      print('Error clearing other users data: $e');
    }
  }

  @override
  Future<void> logoutUser() async {
    await _stopRealtimeSync();
    
    // IMPORTANT: Clear ALL SQLite data on logout to prevent old data from appearing
    // This ensures each login starts fresh from Firebase
    await _dbHelper.clearAllData();
    
    // Clear state
    _state = AppState(
      customers: <Customer>[], 
      credits: <CreditEntry>[], 
      currentUser: null
    );
    notifyListeners();
  }

  Future<void> clearAllData() async {
    await _stopRealtimeSync();
    
    // Clear SQLite database
    await _dbHelper.clearAllData();
    
    // Clear Firebase database (if online)
    try {
      await _connectivityService.initialize();
      if (_connectivityService.isOnline) {
        await _firebaseService.initialize();
        await _firebaseService.clearAllData();
      }
    } catch (e) {
      print('Error clearing Firebase: $e');
      // Continue even if Firebase clear fails - SQLite is already cleared
    }
    
    // Clear in-memory state
    _state = AppState(
      customers: <Customer>[], 
      credits: <CreditEntry>[], 
      currentUser: null
    );
    notifyListeners();
  }

  /// Clear all transaction data (credits, payments) for the current store only
  /// Also removes customers that only had credits with this store
  /// Does NOT delete users or other stores' data
  Future<void> clearStoreTransactionData() async {
    final user = _state.currentUser;
    if (user == null || user.role != UserRole.storeOwner) {
      throw Exception('Only store owners can clear store transaction data');
    }
    
    final storeId = user.id;
    
    // Clear SQLite database for this store
    await _dbHelper.clearStoreTransactionData(storeId);
    
    // Clear Firebase database for this store (if online)
    try {
      await _connectivityService.initialize();
      if (_connectivityService.isOnline) {
        await _firebaseService.initialize();
        await _firebaseService.clearStoreTransactionData(storeId);
      }
    } catch (e) {
      print('Error clearing Firebase store data: $e');
      // Continue even if Firebase clear fails - SQLite is already cleared
    }
    
    // Refresh state from database to reflect the cleared data
    await _setStateFromDatabase(user);
    notifyListeners();
  }

  Future<void> clearSharedPreferences() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_themeKey);
    await clearAllData();
  }

  // Get total amount paid by all customers
  double getTotalAmountPaid() {
    double totalPaid = 0.0;
    for (final credit in _state.credits) {
      totalPaid += credit.paidAmount;
    }
    return totalPaid;
  }

  // Get customers who have fully paid
  List<Customer> getCustomersWhoFullyPaid() {
    final List<Customer> fullyPaidCustomers = [];
    for (final customer in _state.customers) {
      final credits = getCustomerCredits(customer.id);
      final hasOutstanding = credits.any((credit) => credit.balance > 0);
      if (!hasOutstanding && credits.isNotEmpty) {
        fullyPaidCustomers.add(customer);
      }
    }
    return fullyPaidCustomers;
  }

  // Get customers who made any payment (partial or full)
  List<Map<String, dynamic>> getCustomersWithPayments() {
    final List<Map<String, dynamic>> customersWithPayments = [];
    for (final customer in _state.customers) {
      final credits = getCustomerCredits(customer.id);
      double totalPaid = 0.0;
      for (final credit in credits) {
        totalPaid += credit.paidAmount;
      }
      if (totalPaid > 0) {
        customersWithPayments.add({
          'customer': customer,
          'totalPaid': totalPaid,
        });
      }
    }
    // Sort by total paid (highest first)
    customersWithPayments.sort((a, b) => (b['totalPaid'] as double).compareTo(a['totalPaid'] as double));
    return customersWithPayments;
  }

  Future<Customer> addCustomer(String name) async {
    // First, try to find an existing user with this username
    User? existingUser;
    try {
      existingUser = await _dbHelper.getUserByUsername(name.trim());
    } catch (e) {
      // User not found, that's okay
    }
    
    // Check if customer already exists in memory
    final existingCustomer = _state.customers.firstWhere(
      (c) => c.name.toLowerCase() == name.trim().toLowerCase(),
      orElse: () => Customer(id: '', name: ''),
    );
    
    if (existingCustomer.id.isNotEmpty) {
      return existingCustomer;
    }
    
    // Use the user's ID if found, otherwise generate a new one
    final customerId = existingUser?.id ?? generateId();
    
    // IMPORTANT: Set storeId to null or empty string so customers created by customers 
    // can be seen by store owners. Store owners will see all customers (with their storeId or null)
    // When a store owner adds credit, the credit will have the storeId, linking it to the store.
    final String? ownerId = _state.currentUser?.role == UserRole.storeOwner ? _state.currentUser?.id : null;
    final Customer c = Customer(id: customerId, name: name.trim(), storeId: ownerId);
    
    // Use insertOrReplace to handle existing customers gracefully
    await _dbHelper.insertOrReplaceCustomer(c);
    
    // Immediately sync to Firebase
    await _syncCustomerToFirebase(c);
    
    // Only add to state if not already present
    if (!_state.customers.any((existing) => existing.id == c.id)) {
      _state.customers.add(c);
    }
    
    notifyListeners();
    return c;
  }

  Future<void> updateCustomer(Customer customer) async {
    await _dbHelper.updateCustomer(customer);
    
    // Immediately sync to Firebase
    await _syncCustomerToFirebase(customer);
    
    final index = _state.customers.indexWhere((c) => c.id == customer.id);
    if (index != -1) {
      _state.customers[index] = customer;
      notifyListeners();
    }
  }

  Future<void> updateUserCreditLimit(double? creditLimit) async {
    if (_state.currentUser == null) {
      throw StateError('No user logged in');
    }
    
    final updatedUser = User(
      id: _state.currentUser!.id,
      email: _state.currentUser!.email,
      username: _state.currentUser!.username,
      storeName: _state.currentUser!.storeName,
      role: _state.currentUser!.role,
      password: _state.currentUser!.password,
      creditLimit: creditLimit,
    );
    
    await _dbHelper.updateUser(updatedUser);
    
    // Immediately sync to Firebase
    try {
      await _connectivityService.initialize();
      if (_connectivityService.isOnline) {
        await _firebaseService.initialize();
        await _firebaseService.updateUser(updatedUser);
      }
    } catch (e) {
      print('Error syncing user credit limit to Firebase: $e');
      // Don't throw - allow app to continue working offline
    }
    
    // Update state
    _state = AppState(
      customers: _state.customers,
      credits: _state.credits,
      currentUser: updatedUser,
    );
    notifyListeners();
  }

  Future<void> deleteCustomer(String customerId) async {
    // Delete from SQLite first
    await _dbHelper.deleteCustomer(customerId);
    _state.customers.removeWhere((c) => c.id == customerId);
    _state.credits.removeWhere((credit) => credit.customerId == customerId);
    
    // Try to delete from Firebase if online
    try {
      await _connectivityService.initialize();
      if (_connectivityService.isOnline) {
        await _firebaseService.initialize();
        await _firebaseService.deleteCustomer(customerId);
      }
    } catch (e) {
      // If offline or error, that's okay - the record is already deleted from SQLite
      // It will be handled by sync service when online
      print('Error deleting customer from Firebase: $e');
    }
    
    notifyListeners();
  }

  // Check if a credit already exists for a customer with the same item and date
  CreditEntry? findExistingCredit({required String customerId, required String item, required DateTime date}) {
    try {
      return _state.credits.firstWhere(
        (credit) => 
          credit.customerId == customerId &&
          credit.item.toLowerCase() == item.toLowerCase() &&
          credit.date.year == date.year &&
          credit.date.month == date.month &&
          credit.date.day == date.day,
      );
    } catch (e) {
      return null;
    }
  }

  // Check if adding credit would exceed store owner's credit limit (per transaction)
  // Returns true if limit is exceeded (warning should be shown), false otherwise
  Future<bool> checkCreditLimit(String customerId, double newCreditAmount) async {
    // Only check store owner's credit limit, not customer's
    if (_state.currentUser == null || _state.currentUser!.role != UserRole.storeOwner) {
      return false; // No limit check for customers
    }
    
    final storeOwner = _state.currentUser!;
    if (storeOwner.creditLimit == null) {
      return false; // No limit set, no warning needed
    }
    
    // Check if the new credit amount (per transaction) exceeds the limit
    // This is a per-transaction limit, not total outstanding
    return newCreditAmount > storeOwner.creditLimit!;
  }
  
  // Get the credit limit warning message details (per transaction)
  Future<Map<String, dynamic>?> getCreditLimitWarning(String customerId, double newCreditAmount) async {
    final wouldExceed = await checkCreditLimit(customerId, newCreditAmount);
    if (!wouldExceed || _state.currentUser == null) {
      return null;
    }
    
    final storeOwner = _state.currentUser!;
    final limit = storeOwner.creditLimit!;
    
    return {
      'newCredit': newCreditAmount,
      'limit': limit,
      'excess': newCreditAmount - limit,
    };
  }

  // Add or update credit - if exists, update amount; if not, create new
  Future<CreditEntry> addOrUpdateCredit({required String customerId, required String item, required double amount, required DateTime date, DateTime? dueDate, int quantity = 1, double? unitPrice}) async {
    try {
      // First check if customer exists in memory
      Customer? customer;
      try {
        customer = _state.customers.firstWhere((c) => c.id == customerId);
      } catch (e) {
        // Customer not in memory, try to fetch from Firebase
        try {
          await _connectivityService.initialize();
          if (_connectivityService.isOnline) {
            await _firebaseService.initialize();
            customer = await _firebaseService.getCustomer(customerId);
            if (customer != null) {
              // Cache the customer locally
              await _dbHelper.insertOrReplaceCustomer(customer, markAsSynced: true);
              addCustomerToMemory(customer);
            }
          }
        } catch (e2) {
          print('Error fetching customer from Firebase: $e2');
        }
      }
      
      if (customer == null) {
        throw StateError('Customer not found with ID: $customerId');
      }

      // Check if a similar credit already exists
      final existingCredit = findExistingCredit(
        customerId: customerId,
        item: item,
        date: date,
      );

      if (existingCredit != null) {
        // Note: Credit limit check is handled in UI with warning dialog (non-blocking)
        
        // Update existing credit amount
        final updatedCredit = CreditEntry(
          id: existingCredit.id,
          customerId: existingCredit.customerId,
          storeId: existingCredit.storeId,
          item: existingCredit.item,
          amount: existingCredit.amount + amount, // Add to existing amount
          quantity: existingCredit.quantity + quantity, // Add to existing quantity
          unitPrice: unitPrice ?? existingCredit.unitPrice, // Use new unitPrice if provided
          date: existingCredit.date,
          dueDate: dueDate ?? existingCredit.dueDate,
        );
        
        // Copy existing payments
        updatedCredit.payments.addAll(existingCredit.payments);
        
        // Update in database
        await _dbHelper.updateCredit(updatedCredit);
        
        // Immediately sync to Firebase
        await _syncCreditToFirebase(updatedCredit);
        
        // Update in state
        final index = _state.credits.indexWhere((c) => c.id == existingCredit.id);
        if (index != -1) {
          _state.credits[index] = updatedCredit;
        }
        
        notifyListeners();
        return updatedCredit;
      } else {
        // Note: Credit limit check is handled in UI with warning dialog (non-blocking)
        
        // Create new credit
        return await addCredit(
          customerId: customerId,
          item: item,
          amount: amount,
          date: date,
          dueDate: dueDate,
          quantity: quantity,
          unitPrice: unitPrice,
        );
      }
    } catch (e) {
      print('Error in addOrUpdateCredit: $e');
      rethrow;
    }
  }

  Future<CreditEntry> addCredit({required String customerId, required String item, required double amount, required DateTime date, DateTime? dueDate, int quantity = 1, double? unitPrice}) async {
    final String? storeId = _state.currentUser?.role == UserRole.storeOwner ? _state.currentUser?.id : null;
    final CreditEntry e = CreditEntry(
      id: generateId(),
      customerId: customerId,
      storeId: storeId,
      item: item.trim(),
      amount: amount,
      quantity: quantity,
      unitPrice: unitPrice,
      date: date,
      dueDate: dueDate,
    );
    
    print('Adding credit: id=${e.id}, customerId=${e.customerId}, storeId=${e.storeId}, item=${e.item}, amount=${e.amount}');
    
    await _dbHelper.insertCredit(e);
    
    // IMPORTANT: When store owner adds credit, add customer to their view (transaction history)
    if (storeId != null && _state.currentUser?.role == UserRole.storeOwner) {
      // Fetch and cache the customer so they appear in the store owner's customer list
      try {
        await _connectivityService.initialize();
        if (_connectivityService.isOnline) {
          await _firebaseService.initialize();
          final customer = await _firebaseService.getCustomer(customerId);
          if (customer != null) {
            await _dbHelper.insertOrReplaceCustomer(customer, markAsSynced: true);
            // Add to state if not already present
            if (!_state.customers.any((existing) => existing.id == customer.id)) {
              _state.customers.add(customer);
            }
          }
        }
      } catch (e) {
        print('Error fetching customer when adding credit: $e');
      }
    }
    
    // Immediately sync to Firebase
    print('Syncing credit ${e.id} to Firebase for customer ${e.customerId}');
    await _syncCreditToFirebase(e);
    print('Credit ${e.id} synced to Firebase successfully');
    
    // Send notification to the customer (push + in-app)
    // Store owner gets in-app notification only
    if (storeId != null) {
      try {
        final storeName = _state.currentUser?.storeName ?? 'Store';
        
        // Send push notification to customer via Firebase
        await _firebaseService.saveNotification(
          userId: customerId, // Send to customer, NOT store owner
          title: 'New Credit Added',
          message: '₱${amount.toStringAsFixed(2)} credit added for ${item.trim()}',
          type: 'credit_added',
          data: {
            'creditId': e.id,
            'storeId': storeId,
            'storeName': storeName,
            'amount': amount,
            'item': item.trim(),
          },
        );
        print('Credit notification sent to customer ${customerId} via Firebase');
        
        // Store owner gets in-app notification (local only, not via Firebase)
        // This will be shown in the UI when they're on the app
        // We'll handle this in the UI layer, not here
      } catch (e) {
        print('Error sending notification: $e');
      }
    }
    
    _state.credits.add(e);
    notifyListeners();
    return e;
  }

  Future<void> addPayment({required String creditId, required double amount, required DateTime date}) async {
    final CreditEntry entry = _state.credits.firstWhere((CreditEntry e) => e.id == creditId, orElse: () => throw StateError('Credit not found'));
    final payment = Payment(id: generateId(), amount: amount, date: date);
    entry.payments.add(payment);
    await _dbHelper.insertPayment(payment, creditId);
    await _dbHelper.updateCredit(entry);
    
    // Immediately sync to Firebase
    await _syncCreditToFirebase(entry);
    await _syncPaymentToFirebase(payment, creditId);
    
    // Send notification to customer (push + in-app)
    // Store owner gets in-app notification only
    try {
      if (entry.storeId != null && entry.customerId.isNotEmpty) {
        // Get store owner info
        final storeOwner = await _dbHelper.getUserById(entry.storeId!);
        final storeName = storeOwner?.storeName ?? _state.currentUser?.storeName ?? 'Store';
        
        // Send push notification to customer via Firebase
        // This will trigger a system-level push notification confirming payment was received
        await _firebaseService.saveNotification(
          userId: entry.customerId, // Send to customer, NOT store owner
          title: 'Payment Received',
          message: 'Your payment of ₱${amount.toStringAsFixed(2)} for ${entry.item} has been recorded. Remaining balance: ₱${entry.balance.toStringAsFixed(2)}',
          type: 'payment_received',
          data: {
            'creditId': entry.id,
            'storeId': entry.storeId,
            'storeName': storeName,
            'amount': amount,
            'item': entry.item,
            'balance': entry.balance,
          },
        );
        print('Payment notification sent to customer ${entry.customerId} via Firebase - will trigger push notification');
      }
    } catch (e) {
      print('Error sending payment notification: $e');
    }
    
    notifyListeners();
  }

  double totalOutstandingForCustomer(String customerId) {
    return _state.credits.where((CreditEntry e) => e.customerId == customerId).fold(0.0, (double sum, CreditEntry e) => sum + e.balance);
  }

  double totalOutstanding() {
    return _state.credits.fold(0.0, (double sum, CreditEntry e) => sum + e.balance);
  }

  List<CreditEntry> chronologicalHistory() {
    final List<CreditEntry> list = List<CreditEntry>.from(_state.credits);
    list.sort((CreditEntry a, CreditEntry b) => a.date.compareTo(b.date));
    return list;
  }

  Future<void> toggleTheme() async {
    try {
      // Toggle the value
      _isDarkMode = !_isDarkMode;
      
      // Save to SharedPreferences FIRST (before notifying)
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_themeKey, _isDarkMode);
      
      // Force a sync to ensure it's written to disk
      await prefs.reload();
      
      // Verify it was saved
      final saved = prefs.getBool(_themeKey);
      if (saved != _isDarkMode) {
        // If save failed, try again
        _isDarkMode = saved ?? false;
        await prefs.setBool(_themeKey, _isDarkMode);
        await prefs.reload();
      }
      
      // Notify listeners AFTER saving to ensure state is correct
      notifyListeners();
      
      print('Theme toggled to: ${_isDarkMode ? "dark" : "light"}');
    } catch (e) {
      print('Error toggling theme: $e');
      // Revert on error
      _isDarkMode = !_isDarkMode;
      notifyListeners();
    }
  }

  Future<void> syncNow() async {
    if (_isSyncing) return; // Prevent multiple simultaneous syncs
    
    _isSyncing = true;
    notifyListeners();

    try {
      // CRITICAL: Push local data to Firebase FIRST (don't fetch and overwrite)
      // This ensures offline payments are pushed, not overwritten by stale Firebase data
      await _syncService.syncNow();
      
      // DO NOT fetch from Firebase here - it would overwrite local changes!
      // Real-time listeners will handle updates from other devices automatically
      // Only update state from local database (which has the synced data)
      final user = await _dbHelper.getUser();
      await _setStateFromDatabase(user);
      
      print('Sync completed: Local data pushed to Firebase, state updated from local database');
    } catch (e) {
      // Handle sync error
      print('Sync error: $e');
      rethrow;
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  // Customer-specific methods
  List<CreditEntry> getCustomerCredits(String customerId) {
    // Owners: only see credits they own for that customer; Customers: see their own credits
    if (_state.currentUser?.role == UserRole.storeOwner) {
      final String ownerId = _state.currentUser!.id;
      return _state.credits.where((credit) => credit.customerId == customerId && credit.storeId == ownerId).toList();
    }
    return _state.credits.where((credit) => credit.customerId == customerId).toList();
  }

  double getCustomerTotalBalance(String customerId) {
    return getCustomerCredits(customerId).fold(0.0, (sum, credit) => sum + credit.balance);
  }

  List<CreditEntry> getCustomerOverdueCredits(String customerId) {
    return getCustomerCredits(customerId).where((credit) => credit.isOverdue).toList();
  }

  List<CreditEntry> getCustomerDueSoonCredits(String customerId) {
    return getCustomerCredits(customerId).where((credit) => credit.dueSoon).toList();
  }

  List<Payment> getCustomerPayments(String customerId) {
    final List<Payment> allPayments = [];
    for (final credit in getCustomerCredits(customerId)) {
      allPayments.addAll(credit.payments);
    }
    allPayments.sort((a, b) => b.date.compareTo(a.date)); // Most recent first
    return allPayments;
  }

  // Get credits from all stores for a customer
  List<CreditEntry> getAllStoreCreditsForCustomer(String customerId) {
    // For customer view, show all credits for them; for owners, limit to their store
    if (_state.currentUser?.role == UserRole.storeOwner) {
      final String ownerId = _state.currentUser!.id;
      return _state.credits.where((credit) => credit.customerId == customerId && credit.storeId == ownerId).toList();
    }
    return _state.credits.where((credit) => credit.customerId == customerId).toList();
  }

  // Find customer by username (useful for store owners)
  Customer? findCustomerByUsername(String username) {
    try {
      return _state.customers.firstWhere(
        (c) => c.name.toLowerCase() == username.toLowerCase(),
      );
    } catch (e) {
      return null;
    }
  }

  // Get customers who have previously been credited (for store owners)
  List<Customer> getPreviouslyCreditedCustomers() {
    if (_state.currentUser?.role != UserRole.storeOwner) {
      return [];
    }
    
    final String ownerId = _state.currentUser!.id;
    final Set<String> creditedCustomerIds = _state.credits
        .where((credit) => credit.storeId == ownerId)
        .map((credit) => credit.customerId)
        .toSet();
    
    return _state.customers
        .where((customer) => creditedCustomerIds.contains(customer.id))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  // Check if customer exists in database (Firebase + SQLite)
  Future<bool> customerExists(String username) async {
    // Only check for existing CUSTOMERS, never create or infer from users
    // 1) In-memory
    final existingCustomer = findCustomerByUsername(username.trim());
    if (existingCustomer != null) return true;

    // 2) SQLite customers table
    try {
      final allCustomers = await _dbHelper.getAllCustomers();
      if (allCustomers.any((c) => c.name.toLowerCase() == username.trim().toLowerCase())) {
        return true;
      }
    } catch (_) {}

    // 3) Firebase - search ALL customers (including those with null storeId created by customers)
    try {
      await _connectivityService.initialize();
      if (_connectivityService.isOnline && _state.currentUser != null) {
        await _firebaseService.initialize();
        
        // Search all customers in Firebase
        final allRemoteCustomers = await _firebaseService.getAllCustomers();
        final trimmedName = username.trim().toLowerCase();
        
        for (final c in allRemoteCustomers) {
          if (c.name.toLowerCase() == trimmedName) {
            // Check if this customer is relevant to current user
            bool shouldInclude = false;
            if (_state.currentUser!.role == UserRole.storeOwner) {
              // IMPORTANT: Store owners can ONLY see customers with transaction history
              // Check if this customer has credits with this store
              final customerCredits = await _firebaseService.getCreditsForStore(_state.currentUser!.id);
              shouldInclude = customerCredits.any((credit) => credit.customerId == c.id);
            } else {
              // Customers only see themselves
              shouldInclude = c.id == _state.currentUser!.id;
            }
            
            if (shouldInclude) {
              return true;
            }
          }
        }
      }
    } catch (e) {
      print('Error checking customer existence in Firebase: $e');
    }

    return false;
  }

  // Refresh credits from Firebase (useful for customers to see credits added on other devices)
  Future<void> refreshCreditsFromFirebase() async {
    if (_state.currentUser == null) return;
    
    try {
      await _connectivityService.initialize();
      if (_connectivityService.isOnline) {
        await _firebaseService.initialize();
        
        if (_state.currentUser!.role == UserRole.customer) {
          // Fetch credits for this customer
          final remoteCredits = await _firebaseService.getCreditsForCustomer(_state.currentUser!.id);
          print('Refreshing credits for customer ${_state.currentUser!.id}: found ${remoteCredits.length} credits');
          
          // Cache all credits
          for (final credit in remoteCredits) {
            await _dbHelper.insertOrReplaceCredit(credit, markAsSynced: true);
          }
          
          // Refresh state
          await _setStateFromDatabase(_state.currentUser);
        } else if (_state.currentUser!.role == UserRole.storeOwner) {
          // Fetch credits for this store
          final remoteCredits = await _firebaseService.getCreditsForStore(_state.currentUser!.id);
          print('Refreshing credits for store ${_state.currentUser!.id}: found ${remoteCredits.length} credits');
          
          // Cache all credits
          for (final credit in remoteCredits) {
            await _dbHelper.insertOrReplaceCredit(credit, markAsSynced: true);
          }
          
          // Refresh state
          await _setStateFromDatabase(_state.currentUser);
        }
      }
    } catch (e) {
      print('Error refreshing credits from Firebase: $e');
    }
  }

  // Refresh customers from Firebase (useful when adding credit to find customers created on other devices)
  Future<void> refreshCustomersFromFirebase() async {
    if (_state.currentUser == null) return;
    
    try {
      await _connectivityService.initialize();
      if (_connectivityService.isOnline) {
        await _firebaseService.initialize();
        
        if (_state.currentUser!.role == UserRole.storeOwner) {
          // Fetch customers with storeId matching this store
          final remoteCustomers = await _firebaseService.getCustomersForStore(_state.currentUser!.id);
          
          // Also fetch customers with null storeId (created by customers)
          final allRemoteCustomers = await _firebaseService.getAllCustomers();
          final customersWithNullStoreId = allRemoteCustomers.where((c) => 
            (c.storeId == null || c.storeId == '') && !remoteCustomers.any((existing) => existing.id == c.id)
          ).toList();
          
          // Cache all customers
          for (final c in remoteCustomers) {
            await _dbHelper.insertOrReplaceCustomer(c, markAsSynced: true);
            if (!_state.customers.any((existing) => existing.id == c.id)) {
              _state.customers.add(c);
            }
          }
          
          for (final c in customersWithNullStoreId) {
            await _dbHelper.insertOrReplaceCustomer(c, markAsSynced: true);
            if (!_state.customers.any((existing) => existing.id == c.id)) {
              _state.customers.add(c);
            }
          }
          
          notifyListeners();
        }
      }
    } catch (e) {
      print('Error refreshing customers from Firebase: $e');
    }
  }

  // Refresh data from database to ensure we have the latest information
  Future<void> refreshData() async {
    try {
      if (_state.currentUser != null) {
        await _setStateFromDatabase(_state.currentUser);
        notifyListeners();
      }
    } catch (e) {
      print('Error refreshing data: $e');
    }
  }

  // Get or create customer by username with proper existence checking
  Future<Customer> getOrCreateCustomerByUsername(String username) async {
    // First check in memory
    final existingCustomer = findCustomerByUsername(username);
    if (existingCustomer != null) {
      return existingCustomer;
    }
    
    // If not in memory, check database
    try {
      final user = await _dbHelper.getUserByUsername(username);
      if (user != null) {
        // User exists, create customer with same ID
        final customer = Customer(id: user.id, name: username.trim());
        await _dbHelper.insertOrReplaceCustomer(customer);
        
        // Add to state if not already present
        if (!_state.customers.any((existing) => existing.id == customer.id)) {
          _state.customers.add(customer);
        }
        
        notifyListeners();
        return customer;
      }
    } catch (e) {
      // User not found, continue to create new customer
    }
    
    // Create new customer
    return await addCustomer(username);
  }

  // Resolve existing customer by name without creating anything
  Future<Customer?> getCustomerByName(String name) async {
    final trimmed = name.trim();
    // In-memory
    final inMem = findCustomerByUsername(trimmed);
    if (inMem != null) return inMem;

    // SQLite
    try {
      final all = await _dbHelper.getAllCustomers();
      for (final c in all) {
        if (c.name.toLowerCase() == trimmed.toLowerCase()) {
          // Cache into memory
          addCustomerToMemory(c);
          return c;
        }
      }
    } catch (_) {}

    // Firebase - search ALL customers (not just for store) to find customers created by customers
    try {
      await _connectivityService.initialize();
      if (_connectivityService.isOnline && _state.currentUser != null) {
        await _firebaseService.initialize();
        
        // Search all customers in Firebase
        final allRemoteCustomers = await _firebaseService.getAllCustomers();
        for (final c in allRemoteCustomers) {
          if (c.name.toLowerCase() == trimmed.toLowerCase()) {
            // Check if this customer is relevant to current user
            bool shouldInclude = false;
            if (_state.currentUser!.role == UserRole.storeOwner) {
              // IMPORTANT: Store owners can ONLY see customers with transaction history
              // Check if this customer has credits with this store
              final customerCredits = await _firebaseService.getCreditsForStore(_state.currentUser!.id);
              shouldInclude = customerCredits.any((credit) => credit.customerId == c.id);
            } else {
              // Customers only see themselves
              shouldInclude = c.id == _state.currentUser!.id;
            }
            
            if (shouldInclude) {
              // Cache locally
              await _dbHelper.insertOrReplaceCustomer(c, markAsSynced: true);
              addCustomerToMemory(c);
              return c;
            }
          }
        }
      }
    } catch (e) {
      print('Error fetching customer from Firebase: $e');
    }

    return null;
  }

  Future<Customer?> getCustomerById(String id) async {
    // Try in-memory first
    try {
      final cust = _state.customers.firstWhere((c) => c.id == id);
      return cust;
    } catch (_) {}
    // Not found in memory, try DB
    try {
      final db = DatabaseHelper();
      final all = await db.getAllCustomers();
      for (final cust in all) {
        if (cust.id == id) return cust;
      }
    } catch (e) {}
    return null;
  }

  Future<void> _setStateFromDatabase(User? user) async {
    List<Customer> customers = <Customer>[];
    List<CreditEntry> credits = <CreditEntry>[];

    if (user != null) {
      // First, try to fetch from Firebase to ensure we have the latest data
      try {
        await _connectivityService.initialize();
        if (_connectivityService.isOnline) {
          await _firebaseService.initialize();
          
          if (user.role == UserRole.storeOwner) {
            // IMPORTANT: Store owners should ONLY see customers with transaction history
            // Fetch credits from Firebase for THIS store owner only
            final remoteCredits = await _firebaseService.getCreditsForStore(user.id);
            
            // Cache credits for this store
            final Set<String> creditCustomerIds = <String>{};
            for (final credit in remoteCredits) {
              await _dbHelper.insertOrReplaceCredit(credit, markAsSynced: true);
              creditCustomerIds.add(credit.customerId);
              
              // Cache the customer for this credit (only customers with transaction history)
              final creditCustomer = await _firebaseService.getCustomer(credit.customerId);
              if (creditCustomer != null) {
                await _dbHelper.insertOrReplaceCustomer(creditCustomer, markAsSynced: true);
              }
            }
            
            // IMPORTANT: Do NOT fetch all customers - only fetch customers who have credits
            // Store owners should NOT see customers without transaction history
          } else {
            // IMPORTANT: Customers should ONLY see their own data
            // For customers, fetch ONLY their own data
            final customer = await _firebaseService.getCustomer(user.id);
            if (customer != null) {
              await _dbHelper.insertOrReplaceCustomer(customer, markAsSynced: true);
            }
            final remoteCredits = await _firebaseService.getCreditsForCustomer(user.id);
            final Set<String> storeOwnerIds = <String>{};
            for (final credit in remoteCredits) {
              if (credit.storeId != null && credit.storeId!.isNotEmpty) {
                storeOwnerIds.add(credit.storeId!);
              }
              await _dbHelper.insertOrReplaceCredit(credit, markAsSynced: true);
            }

            // Cache store owner information locally so the customer can see store names even offline
            for (final storeId in storeOwnerIds) {
              try {
                final storeOwner = await _firebaseService.getUser(storeId);
                if (storeOwner != null) {
                  await _dbHelper.insertOrReplaceUser(storeOwner);
                }
              } catch (e) {
                print('Error caching store owner $storeId for customer credits: $e');
              }
            }
          }
        }
      } catch (e) {
        print('Error fetching from Firebase in _setStateFromDatabase: $e');
        // Continue with local data if Firebase fetch fails
      }

      // Now load from local database (which may have been updated from Firebase)
      // IMPORTANT: Only load data that belongs to this user
      if (user.role == UserRole.storeOwner) {
        // Store owners: ONLY customers who have credits with this store (transaction history)
        credits = await _dbHelper.getCreditsByStoreId(user.id);
        
        // Get unique customer IDs from credits (customers with transaction history)
        final Set<String> creditCustomerIds = credits.map((c) => c.customerId).toSet();
        
        // Only fetch customers who have credits with this store
        if (creditCustomerIds.isNotEmpty) {
          customers = await _dbHelper.getCustomersByIds(creditCustomerIds.toList());
        } else {
          customers = [];
        }
        
        // IMPORTANT: Store owners should NOT see customers without transaction history
        // They can only see customers they've already added credit to
      } else {
        // Customers: Only their own data - query directly instead of loading all
        final customer = await _dbHelper.getCustomerById(user.id);
        if (customer != null) {
          customers = [customer];
        } else {
          customers = [];
        }
        
        // Only get credits for this customer
        credits = await _dbHelper.getCreditsByCustomerId(user.id);
      }
    } else {
      customers = await _dbHelper.getAllCustomers();
      credits = await _dbHelper.getAllCredits();
    }

    _state = AppState(customers: customers, credits: credits, currentUser: user);
    notifyListeners();
  }

  Future<void> _startRealtimeSyncForCurrentUser() async {
    await _stopRealtimeSync();
    final user = _state.currentUser;
    if (user == null) return;

    try {
      await _firebaseService.initialize();
      
      // Ensure Firebase is ready - simple check without blocking
      final auth = _firebaseService.auth;
      print('Starting real-time sync for user: ${user.id}, auth ready: ${auth.currentUser != null}');
      
      // Enable keepSynced to ensure data is always fresh (not cached)
      // This is critical for real devices which may use cached data
      await _firebaseService.database.child('credits').keepSynced(true);
      await _firebaseService.database.child('payments').keepSynced(true);
      await _firebaseService.database.child('customers').keepSynced(true);
      await _firebaseService.database.child('notifications').child(user.id).keepSynced(true);
      await _firebaseService.database.child('users').child(user.id).keepSynced(true);
    } catch (e) {
      print('Realtime sync init error: $e');
      return;
    }

    void creditHandler(DatabaseEvent event) async {
      // Handle both null and non-null snapshots
      if (event.snapshot.value == null) {
        print('Credit handler: No data in snapshot (empty credits)');
        await _setStateFromDatabase(user);
        notifyListeners();
        return;
      }
      
      final creditsData = event.snapshot.value;
      
      print('Credit handler: Received data for user ${user.id} (role: ${user.role})');
      
      if (creditsData is Map) {
        // Fetch ALL payments once at the start (efficient - single Firebase call)
        final allPaymentsSnapshot = await _firebaseService.database.child('payments').get();
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
                  date: DateTime.fromMillisecondsSinceEpoch(paymentData['date'] as int? ?? DateTime.now().millisecondsSinceEpoch),
                ),
              );
            }
          }
        }
        
        // Get local credits for comparison
        final localCredits = user.role == UserRole.storeOwner
            ? await _dbHelper.getCreditsByStoreId(user.id)
            : await _dbHelper.getCreditsByCustomerId(user.id);
        final firebaseCreditIds = creditsData.keys.toSet();
        
        // Handle removed credits
        for (final localCredit in localCredits) {
          if (!firebaseCreditIds.contains(localCredit.id)) {
            print('Credit handler: Deleting credit ${localCredit.id} (not in Firebase)');
            await _dbHelper.deleteCredit(localCredit.id);
          }
        }
        
        // Handle added/updated credits - parse directly from snapshot
        for (final entry in creditsData.entries) {
          final creditId = entry.key;
          final creditData = entry.value;
          
          if (creditData is Map) {
            try {
              // Verify this credit is relevant to the current user
              final creditStoreId = creditData['storeId'];
              final creditCustomerId = creditData['customerId'] ?? '';
              bool shouldInclude = false;
              
              if (user.role == UserRole.storeOwner) {
                shouldInclude = creditStoreId == user.id;
              } else if (user.role == UserRole.customer) {
                shouldInclude = creditCustomerId == user.id;
              }
              
              if (!shouldInclude) {
                continue;
              }
              
              // CRITICAL: Check if this credit is unsynced locally
              // If unsynced, don't overwrite it - it will be pushed by sync service
              final unsyncedCredits = await _dbHelper.getUnsyncedRecords('credits');
              final isUnsynced = unsyncedCredits.any((c) => c['id'] == creditId);
              
              if (isUnsynced) {
                print('Credit handler: Skipping credit $creditId - it has unsynced local changes that will be pushed');
                continue; // Skip this credit, let sync service push it first
              }
              
              // Get payments for this credit from the pre-fetched map
              final payments = paymentsByCreditId[creditId] ?? [];

              final credit = CreditEntry(
                id: creditId,
                customerId: creditCustomerId,
                storeId: creditStoreId,
                item: creditData['item'] ?? '',
                amount: (creditData['amount'] as num).toDouble(),
                quantity: creditData['quantity'] != null ? (creditData['quantity'] as num).toInt() : 1,
                unitPrice: creditData['unitPrice'] != null ? (creditData['unitPrice'] as num).toDouble() : null,
                date: DateTime.fromMillisecondsSinceEpoch(creditData['date'] as int? ?? DateTime.now().millisecondsSinceEpoch),
                dueDate: creditData['dueDate'] != null ? DateTime.fromMillisecondsSinceEpoch(creditData['dueDate'] as int) : null,
              );
              
              credit.payments.addAll(payments);
              
              // Only update if credit is already synced (no local changes)
              await _dbHelper.insertOrReplaceCredit(credit, markAsSynced: true);
              
              // Fetch and cache customer if needed
              final customer = await _firebaseService.getCustomer(credit.customerId);
              if (customer != null) {
                await _dbHelper.insertOrReplaceCustomer(customer, markAsSynced: true);
                if (!_state.customers.any((c) => c.id == customer.id)) {
                  _state.customers.add(customer);
                }
              }
            } catch (e) {
              print('Credit handler: Error parsing credit $creditId: $e');
            }
          }
        }
      } else if (creditsData is Map && creditsData.isEmpty) {
        print('Credit handler: Empty credits map, refreshing state');
        await _setStateFromDatabase(user);
        notifyListeners();
        return;
      }

      // Always refresh state and notify listeners to ensure UI updates
      await _setStateFromDatabase(user);
      notifyListeners();
    }

    void customerHandler(DatabaseEvent event) async {
      if (event.snapshot.value == null) return;
      
      bool changed = false;
      final customersData = event.snapshot.value;
      
      if (customersData is Map) {
        // Handle removed customers (check if any local customers are not in Firebase)
        final localCustomers = await _dbHelper.getAllCustomers();
        final firebaseCustomerIds = customersData.keys.toSet();
        
        for (final localCustomer in localCustomers) {
          if (user.role == UserRole.storeOwner) {
            // For store owners, check customers for their store OR null storeId (created by customers)
            if (localCustomer.storeId != user.id && 
                localCustomer.storeId != null && 
                localCustomer.storeId != '') continue;
          } else if (user.role == UserRole.customer) {
            // For customers, only check their own record
            if (localCustomer.id != user.id) continue;
          }
          
          if (!firebaseCustomerIds.contains(localCustomer.id)) {
            // Customer was deleted in Firebase
            await _dbHelper.deleteCustomer(localCustomer.id);
            changed = true;
          }
        }
        
        // Handle added/updated customers
        for (final entry in customersData.entries) {
          final customerId = entry.key;
          final customerData = entry.value;
          
          if (customerData is Map) {
            // Check if this customer is relevant to the current user
            final storeId = customerData['storeId'];
            bool shouldInclude = false;
            
            if (user.role == UserRole.storeOwner) {
              // Store owners can see customers with their storeId OR null storeId (created by customers)
              shouldInclude = storeId == user.id || storeId == null || storeId == '';
            } else {
              // Customers only see themselves
              shouldInclude = customerId == user.id;
            }
            
            if (shouldInclude) {
              final customer = await _firebaseService.getCustomer(customerId);
              if (customer != null) {
                await _dbHelper.insertOrReplaceCustomer(customer, markAsSynced: true);
                changed = true;
              }
            }
          }
        }
      }

      if (changed) {
        await _setStateFromDatabase(user);
        // Force notify listeners to ensure UI updates
        notifyListeners();
      }
    }

    // Set up credit listeners with error handling and auto-reconnect
    if (user.role == UserRole.customer) {
      print('Setting up credit listener for customer: ${user.id}');
      _creditSubscription = _firebaseService
          .listenToCreditsForCustomer(user.id)
          .listen(
            (event) {
              print('Credit listener triggered for customer ${user.id}');
              creditHandler(event);
            },
            onError: (error) {
              print('Credit listener error for customer ${user.id}: $error');
              // Try to reconnect after a delay - critical for real devices
              Future.delayed(const Duration(seconds: 3), () {
                if (_state.currentUser?.id == user.id) {
                  print('Attempting to reconnect credit listener for customer ${user.id}');
                  _startRealtimeSyncForCurrentUser();
                }
              });
            },
            cancelOnError: false, // Don't cancel on error, keep trying
          );
      print('Credit listener active for customer: ${user.id}');
    } else if (user.role == UserRole.storeOwner) {
      print('Setting up credit listener for store owner: ${user.id}');
      _creditSubscription = _firebaseService
          .listenToCreditsForStore(user.id)
          .listen(
            (event) {
              print('Credit listener triggered for store owner ${user.id}');
              creditHandler(event);
            },
            onError: (error) {
              print('Credit listener error for store owner ${user.id}: $error');
              // Try to reconnect after a delay - critical for real devices
              Future.delayed(const Duration(seconds: 3), () {
                if (_state.currentUser?.id == user.id) {
                  print('Attempting to reconnect credit listener for store owner ${user.id}');
                  _startRealtimeSyncForCurrentUser();
                }
              });
            },
            cancelOnError: false, // Don't cancel on error, keep trying
          );
      print('Credit listener active for store owner: ${user.id}');
    }

    // Set up customer listeners
    if (user.role == UserRole.storeOwner) {
      // Store owners listen to all customers (to see customers created on other devices)
      _customerSubscription = _firebaseService
          .listenToAllCustomers()
          .listen(
            customerHandler,
            onError: (error) {
              print('Customer listener error: $error');
            },
            cancelOnError: false,
          );
    } else if (user.role == UserRole.customer) {
      // Customers only listen to their own record
      _customerSubscription = _firebaseService
          .listenToAllCustomers()
          .listen(
            customerHandler,
            onError: (error) {
              print('Customer listener error: $error');
            },
            cancelOnError: false,
          );
    }

    // Payment listener: When payments change, refresh affected credits
    // CRITICAL: This must work on real devices with poor network conditions
    void paymentHandler(DatabaseEvent event) async {
      if (event.snapshot.value == null) return;
      
      print('Payment handler: Payment data changed, triggering credit refresh for user ${user.id}');
      
      try {
        // Get affected credit IDs from the payment data
        final paymentsData = event.snapshot.value;
        final Set<String> affectedCreditIds = {};
        
        if (paymentsData is Map) {
          for (final paymentEntry in paymentsData.entries) {
            final paymentData = Map<String, dynamic>.from(paymentEntry.value as Map);
            final paymentCreditId = paymentData['creditId'] as String?;
            if (paymentCreditId != null) {
              // Check if this credit is relevant to the current user
              bool isRelevant = false;
              if (user.role == UserRole.storeOwner) {
                // For store owners, we need to check if the credit belongs to their store
                // We'll fetch the credit to check
                try {
                  final creditSnapshot = await _firebaseService.database
                      .child('credits')
                      .child(paymentCreditId)
                      .get();
                  if (creditSnapshot.exists && creditSnapshot.value != null) {
                    final creditData = Map<String, dynamic>.from(creditSnapshot.value as Map);
                    isRelevant = creditData['storeId'] == user.id;
                  }
                } catch (e) {
                  print('Payment handler: Error checking credit $paymentCreditId: $e');
                }
              } else if (user.role == UserRole.customer) {
                // For customers, check if the credit belongs to them
                try {
                  final creditSnapshot = await _firebaseService.database
                      .child('credits')
                      .child(paymentCreditId)
                      .get();
                  if (creditSnapshot.exists && creditSnapshot.value != null) {
                    final creditData = Map<String, dynamic>.from(creditSnapshot.value as Map);
                    isRelevant = creditData['customerId'] == user.id;
                  }
                } catch (e) {
                  print('Payment handler: Error checking credit $paymentCreditId: $e');
                }
              }
              
              if (isRelevant) {
                affectedCreditIds.add(paymentCreditId);
              }
            }
          }
        }
        
        if (affectedCreditIds.isEmpty) {
          print('Payment handler: No relevant credits affected');
          return;
        }
        
        print('Payment handler: Refreshing ${affectedCreditIds.length} affected credits');
        
        // Fetch and update each affected credit with fresh data from Firebase
        // Use direct Firebase queries to avoid cached data
        for (final creditId in affectedCreditIds) {
          try {
            // CRITICAL: Check if this credit is unsynced locally
            // If unsynced, don't overwrite it - it will be pushed by sync service
            final unsyncedCredits = await _dbHelper.getUnsyncedRecords('credits');
            final isUnsynced = unsyncedCredits.any((c) => c['id'] == creditId);
            
            if (isUnsynced) {
              print('Payment handler: Skipping credit $creditId - it has unsynced local changes that will be pushed');
              continue; // Skip this credit, let sync service push it first
            }
            
            // Fetch credit with all payments directly from Firebase (fresh data)
            final credit = await _firebaseService.getCredit(creditId);
            if (credit != null) {
              // Verify it's still relevant
              bool shouldUpdate = false;
              if (user.role == UserRole.storeOwner) {
                shouldUpdate = credit.storeId == user.id;
              } else if (user.role == UserRole.customer) {
                shouldUpdate = credit.customerId == user.id;
              }
              
              if (shouldUpdate) {
                await _dbHelper.insertOrReplaceCredit(credit, markAsSynced: true);
                print('Payment handler: Updated credit $creditId with balance ${credit.balance}');
              }
            }
          } catch (e) {
            print('Payment handler: Error updating credit $creditId: $e');
          }
        }
        
        // Refresh state from database to update UI
        await _setStateFromDatabase(user);
        notifyListeners();
        print('Payment handler: State refreshed and listeners notified');
      } catch (e) {
        print('Payment handler: Error refreshing credits: $e');
        // Even on error, try to refresh state
        try {
          await _setStateFromDatabase(user);
          notifyListeners();
        } catch (e2) {
          print('Payment handler: Error in fallback refresh: $e2');
        }
      }
    }
    
    // Set up payment listener - triggers when payments change
    // CRITICAL: This must work reliably on real devices
    _paymentSubscription = _firebaseService.database
        .child('payments')
        .onValue
        .listen(
          (event) {
            print('Payment listener triggered for user ${user.id}');
            paymentHandler(event);
          },
          onError: (error) {
            print('Payment listener error for user ${user.id}: $error');
            // Try to reconnect after a delay - critical for real devices
            Future.delayed(const Duration(seconds: 3), () {
              if (_state.currentUser?.id == user.id) {
                print('Attempting to reconnect payment listener for user ${user.id}');
                _startRealtimeSyncForCurrentUser();
              }
            });
          },
          cancelOnError: false,
        );
    print('Payment listener active for user: ${user.id}');

    // Set up notification listener for real-time notifications
    // CRITICAL: Must work reliably on real devices
    await _notificationService.initialize();
    void notificationHandler(DatabaseEvent event) async {
      print('Notification handler: Received notification event for user ${user.id}');
      
      try {
        // Handle both onValue (all notifications) and onChildAdded (single notification)
        Map<String, dynamic> notificationsData;
        
        if (event.snapshot.value is Map) {
          // onValue event - contains all notifications
          notificationsData = Map<String, dynamic>.from(event.snapshot.value as Map);
        } else if (event.snapshot.value != null) {
          // onChildAdded event - single notification, wrap it
          final notificationId = event.snapshot.key ?? DateTime.now().millisecondsSinceEpoch.toString();
          notificationsData = {
            notificationId: event.snapshot.value,
          };
        } else {
          print('Notification handler: No notification data');
          return;
        }
        
        if (notificationsData.isNotEmpty) {
          // Get the most recent unread notification
          final notifications = notificationsData.entries.toList();
          notifications.sort((a, b) {
            final aData = a.value as Map?;
            final bData = b.value as Map?;
            final aCreated = aData?['createdAt'] as int? ?? 0;
            final bCreated = bData?['createdAt'] as int? ?? 0;
            return bCreated.compareTo(aCreated); // Most recent first
          });
          
          // Process ALL unread notifications (not just the first one)
          // This ensures credit_added notifications trigger push notifications like manual ones
          final List<MapEntry<String, dynamic>> unreadNotifications = [];
          for (final entry in notifications) {
            final notificationData = entry.value;
            if (notificationData is Map) {
              final read = notificationData['read'] as bool? ?? false;
              if (!read) {
                unreadNotifications.add(entry);
              }
            }
          }
          
          // Process ALL unread notifications to trigger push notifications
          // This ensures credit_added notifications work the same as manual notifications
          for (final entry in unreadNotifications) {
            final notificationData = entry.value as Map;
            final title = notificationData['title'] as String? ?? 'Notification';
            final message = notificationData['message'] as String? ?? '';
            final type = notificationData['type'] as String? ?? 'info';
            
            print('Notification handler: Processing notification - $title: $message for user ${user.id} (type: $type)');
            
            // Determine notification type
            NotificationType notifType = NotificationType.info;
            if (type == 'credit_added' || type == 'payment_reminder') {
              notifType = NotificationType.info;
            } else if (type == 'payment_received') {
              notifType = NotificationType.success;
            } else if (type == 'due_soon' || type == 'overdue') {
              notifType = NotificationType.warning;
            }
            
            // For CUSTOMERS: Show both system-level push AND in-app notification
            // For STORE OWNERS: Only in-app (they shouldn't receive push for their own actions)
            if (user.role == UserRole.customer) {
              // CRITICAL: Show system-level push notification for ALL notification types
              // This ensures credit_added notifications trigger push notifications like manual ones
              await _notificationService.showInstantNotification(
                title: title,
                message: message,
                type: notifType,
              );
              print('Notification handler: System push notification shown for customer ${user.id} - $title: $message');
              
              // In-app notification will be handled by the UI when they open the app
              // The notification listener will trigger UI updates via notifyListeners()
            } else {
              // Store owners: Only show in-app (no push for their own actions)
              // This will be handled in the UI layer
              print('Notification handler: Store owner notification (in-app only) for ${user.id}');
            }
            
            // Mark as read after showing
            try {
              await _firebaseService.markNotificationAsRead(user.id, entry.key);
              print('Notification handler: Marked notification ${entry.key} as read');
            } catch (e) {
              print('Notification handler: Error marking notification as read: $e');
            }
          }
        }
      } catch (e) {
        print('Notification handler: Error processing notifications: $e');
      }
    }
    
    // Use onValue directly for better real-time updates on real devices
    // orderByChild can be slow on real devices, so we'll sort in the handler instead
    _notificationSubscription = _firebaseService.database
        .child('notifications')
        .child(user.id)
        .onValue
        .listen(
          (event) {
            print('Notification listener triggered for user ${user.id}');
            notificationHandler(event);
          },
          onError: (error) {
            print('Notification listener error for user ${user.id}: $error');
            // Try to reconnect after a delay - critical for real devices
            Future.delayed(const Duration(seconds: 3), () {
              if (_state.currentUser?.id == user.id) {
                print('Attempting to reconnect notification listener for user ${user.id}');
                _startRealtimeSyncForCurrentUser();
              }
            });
          },
          cancelOnError: false,
        );
    print('Notification listener active for user: ${user.id} (using onValue for real-time updates)');
    
    // Set up user listener for credit limit syncing
    // CRITICAL: Real phones need to receive credit limit updates
    void userHandler(DatabaseEvent event) async {
      if (event.snapshot.value == null) return;
      
      print('User handler: Received user update for ${user.id}');
      
      try {
        final userData = event.snapshot.value;
        if (userData is Map) {
          final creditLimit = userData['creditLimit'] != null 
              ? (userData['creditLimit'] as num).toDouble() 
              : null;
          
          // Update local user if credit limit changed
          if (_state.currentUser != null && _state.currentUser!.creditLimit != creditLimit) {
            print('User handler: Credit limit changed from ${_state.currentUser!.creditLimit} to $creditLimit');
            
            final updatedUser = User(
              id: _state.currentUser!.id,
              email: _state.currentUser!.email,
              username: _state.currentUser!.username,
              storeName: _state.currentUser!.storeName,
              role: _state.currentUser!.role,
              password: _state.currentUser!.password,
              creditLimit: creditLimit,
            );
            
            await _dbHelper.updateUser(updatedUser);
            _state = AppState(
              customers: _state.customers,
              credits: _state.credits,
              currentUser: updatedUser,
            );
            notifyListeners();
            print('User handler: Credit limit updated and state refreshed');
          }
        }
      } catch (e) {
        print('User handler: Error processing user update: $e');
      }
    }
    
    _userSubscription = _firebaseService.database
        .child('users')
        .child(user.id)
        .onValue
        .listen(
          (event) {
            print('User listener triggered for user ${user.id}');
            userHandler(event);
          },
          onError: (error) {
            print('User listener error for user ${user.id}: $error');
            // Try to reconnect after a delay
            Future.delayed(const Duration(seconds: 3), () {
              if (_state.currentUser?.id == user.id) {
                print('Attempting to reconnect user listener for user ${user.id}');
                _startRealtimeSyncForCurrentUser();
              }
            });
          },
          cancelOnError: false,
        );
    print('User listener active for user: ${user.id}');
    
    // Real-time listeners are the primary mechanism for updates
    // No periodic refresh - updates happen automatically when credits/payments change
  }

  Future<void> _stopRealtimeSync() async {
    try {
      await _creditSubscription?.cancel();
      await _customerSubscription?.cancel();
      await _paymentSubscription?.cancel();
      await _notificationSubscription?.cancel();
      await _userSubscription?.cancel();
    } catch (e) {
      print('Error stopping realtime sync: $e');
    } finally {
      _creditSubscription = null;
      _customerSubscription = null;
      _paymentSubscription = null;
      _notificationSubscription = null;
      _userSubscription = null;
    }
  }

  // Public method to restart real-time sync (useful when app resumes)
  Future<void> restartRealtimeSync() async {
    if (_state.currentUser != null) {
      print('Restarting real-time sync for user ${_state.currentUser!.id}');
      await _startRealtimeSyncForCurrentUser();
    }
  }

  Future<void> _downloadAndCacheUserData(User user) async {
    try {
      await _firebaseService.initialize();

      if (user.role == UserRole.storeOwner) {
        final remoteCustomers = await _firebaseService.getCustomersForStore(user.id);
        final remoteCredits = await _firebaseService.getCreditsForStore(user.id);
        final Set<String> customerIds = remoteCustomers.map((c) => c.id).toSet();

        for (final customer in remoteCustomers) {
          await _dbHelper.insertOrReplaceCustomer(customer, markAsSynced: true);
        }

        for (final credit in remoteCredits) {
          await _dbHelper.insertOrReplaceCredit(credit, markAsSynced: true);
          if (!customerIds.contains(credit.customerId)) {
            final extraCustomer = await _firebaseService.getCustomer(credit.customerId);
            if (extraCustomer != null) {
              await _dbHelper.insertOrReplaceCustomer(extraCustomer, markAsSynced: true);
              customerIds.add(extraCustomer.id);
            }
          }
        }
      } else {
        final customer = await _firebaseService.getCustomer(user.id);
        if (customer != null) {
          await _dbHelper.insertOrReplaceCustomer(customer, markAsSynced: true);
        }

        final remoteCredits = await _firebaseService.getCreditsForCustomer(user.id);
        for (final credit in remoteCredits) {
          await _dbHelper.insertOrReplaceCredit(credit, markAsSynced: true);
        }
      }
    } catch (e) {
      print('Error downloading user data: $e');
    }
  }
 
  // Safely add a customer to memory and notify listeners
  void addCustomerToMemory(Customer customer) {
    if (!_state.customers.any((c) => c.id == customer.id)) {
      _state.customers.add(customer);
      notifyListeners();
    }
  }

  // Helper methods to immediately sync to Firebase
  Future<void> _syncUserToFirebase(User user) async {
    try {
      await _connectivityService.initialize();
      if (_connectivityService.isOnline) {
        await _firebaseService.initialize();
        await _firebaseService.saveUser(user);
        await _dbHelper.markAsSynced('users', user.id);
      }
    } catch (e) {
      print('Error syncing user to Firebase: $e');
      // Don't throw - allow app to continue working offline
    }
  }

  Future<void> _syncCustomerToFirebase(Customer customer) async {
    try {
      await _connectivityService.initialize();
      if (_connectivityService.isOnline) {
        await _firebaseService.initialize();
        await _firebaseService.saveCustomer(customer);
        await _dbHelper.markAsSynced('customers', customer.id);
      }
    } catch (e) {
      print('Error syncing customer to Firebase: $e');
      // Don't throw - allow app to continue working offline
    }
  }

  Future<void> _syncCreditToFirebase(CreditEntry credit) async {
    try {
      await _connectivityService.initialize();
      if (_connectivityService.isOnline) {
        await _firebaseService.initialize();
        print('_syncCreditToFirebase: Saving credit ${credit.id} to Firebase (customerId: ${credit.customerId}, storeId: ${credit.storeId})');
        await _firebaseService.saveCredit(credit);
        print('_syncCreditToFirebase: Credit ${credit.id} saved successfully');
        await _dbHelper.markAsSynced('credits', credit.id);
        // Mark all payments as synced too
        for (final payment in credit.payments) {
          await _dbHelper.markAsSynced('payments', payment.id);
        }
      } else {
        print('_syncCreditToFirebase: Device is offline, credit will sync when online');
      }
    } catch (e) {
      print('Error syncing credit to Firebase: $e');
      // Don't throw - allow app to continue working offline
    }
  }

  Future<void> _syncPaymentToFirebase(Payment payment, String creditId) async {
    try {
      await _connectivityService.initialize();
      if (_connectivityService.isOnline) {
        await _firebaseService.initialize();
        await _firebaseService.savePayment(payment, creditId);
        await _dbHelper.markAsSynced('payments', payment.id);
      }
    } catch (e) {
      print('Error syncing payment to Firebase: $e');
      // Don't throw - allow app to continue working offline
    }
  }
}


