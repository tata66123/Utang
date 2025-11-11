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
  StreamSubscription<DatabaseEvent>? _creditSubscription;

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
      // Initialize sync service
      await _syncService.initialize();
      await _firebaseService.initialize();
      
      // Load data from SQLite
      final user = await _dbHelper.getUser();
      await _setStateFromDatabase(user);

      // Load theme preference
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      _isDarkMode = prefs.getBool(_themeKey) ?? false;
      
      notifyListeners();
      await _startRealtimeSyncForCurrentUser();
      
      // Try to sync in background
      if (!_isSyncing) {
        _syncInBackground();
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
      // Query the local database first
      final localUser = await _dbHelper.getUserByUsername(username);
      if (localUser != null && (localUser.password == null || localUser.password == password)) {
        await _setStateFromDatabase(localUser);
        await _startRealtimeSyncForCurrentUser();
        return true;
      }

      // Fallback to Firebase
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

      await _dbHelper.insertOrReplaceUser(remoteUser);
      await _downloadAndCacheUserData(remoteUser);
      await _setStateFromDatabase(remoteUser);
      await _startRealtimeSyncForCurrentUser();
      return true;
    } catch (e) {
      print('Login error: $e');
      return false;
    }
  }

  @override
  Future<void> logoutUser() async {
    await _stopRealtimeSync();
    // Just clear the current user from state, don't delete from database
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

  // Check if adding credit would exceed customer's credit limit
  void checkCreditLimit(String customerId, double newCreditAmount) {
    final customer = _state.customers.firstWhere(
      (c) => c.id == customerId,
      orElse: () => throw StateError('Customer not found with ID: $customerId'),
    );
    
    if (customer.creditLimit != null) {
      final currentTotalBalance = totalOutstandingForCustomer(customerId);
      final newTotalBalance = currentTotalBalance + newCreditAmount;
      
      if (newTotalBalance > customer.creditLimit!) {
        throw StateError(
          'Credit limit exceeded! Current balance: ₱${currentTotalBalance.toStringAsFixed(2)}, '
          'New credit: ₱${newCreditAmount.toStringAsFixed(2)}, '
          'Total would be: ₱${newTotalBalance.toStringAsFixed(2)}, '
          'Limit: ₱${customer.creditLimit!.toStringAsFixed(2)}'
        );
      }
    }
  }

  // Add or update credit - if exists, update amount; if not, create new
  Future<CreditEntry> addOrUpdateCredit({required String customerId, required String item, required double amount, required DateTime date, DateTime? dueDate}) async {
    try {
      // First check if customer exists (validation check)
      _state.customers.firstWhere(
        (c) => c.id == customerId,
        orElse: () => throw StateError('Customer not found with ID: $customerId'),
      );

      // Check if a similar credit already exists
      final existingCredit = findExistingCredit(
        customerId: customerId,
        item: item,
        date: date,
      );

      if (existingCredit != null) {
        // Calculate the additional amount being added
        final additionalAmount = amount;
        
        // Check credit limit before updating
        checkCreditLimit(customerId, additionalAmount);
        
        // Update existing credit amount
        final updatedCredit = CreditEntry(
          id: existingCredit.id,
          customerId: existingCredit.customerId,
          storeId: existingCredit.storeId,
          item: existingCredit.item,
          amount: existingCredit.amount + amount, // Add to existing amount
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
        // Check credit limit before creating new credit
        checkCreditLimit(customerId, amount);
        
        // Create new credit
        return await addCredit(
          customerId: customerId,
          item: item,
          amount: amount,
          date: date,
          dueDate: dueDate,
        );
      }
    } catch (e) {
      print('Error in addOrUpdateCredit: $e');
      rethrow;
    }
  }

  Future<CreditEntry> addCredit({required String customerId, required String item, required double amount, required DateTime date, DateTime? dueDate}) async {
    final String? storeId = _state.currentUser?.role == UserRole.storeOwner ? _state.currentUser?.id : null;
    final CreditEntry e = CreditEntry(
      id: generateId(),
      customerId: customerId,
      storeId: storeId,
      item: item.trim(),
      amount: amount,
      date: date,
      dueDate: dueDate,
    );
    await _dbHelper.insertCredit(e);
    
    // Immediately sync to Firebase
    await _syncCreditToFirebase(e);
    
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
    _isDarkMode = !_isDarkMode;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_themeKey, _isDarkMode);
    notifyListeners();
  }

  Future<void> syncNow() async {
    _isSyncing = true;
    notifyListeners();

    try {
      await _syncService.syncNow();
      final user = await _dbHelper.getUser();
      await _setStateFromDatabase(user);
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

    // 3) Firebase customers for current store (if online)
    try {
      await _connectivityService.initialize();
      if (_connectivityService.isOnline && _state.currentUser != null) {
        await _firebaseService.initialize();
        final storeId = _state.currentUser!.role == UserRole.storeOwner ? _state.currentUser!.id : _state.currentUser!.id;
        final remoteCustomers = await _firebaseService.getCustomersForStore(storeId);
        if (remoteCustomers.any((c) => c.name.toLowerCase() == username.trim().toLowerCase())) {
          return true;
        }
      }
    } catch (_) {}

    return false;
  }

  // Refresh data from database to ensure we have the latest information
  Future<void> refreshData() async {
    try {
      await _setStateFromDatabase(_state.currentUser);
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

    // Firebase (for current store)
    try {
      await _connectivityService.initialize();
      if (_connectivityService.isOnline && _state.currentUser != null) {
        await _firebaseService.initialize();
        final storeId = _state.currentUser!.role == UserRole.storeOwner ? _state.currentUser!.id : _state.currentUser!.id;
        final remoteCustomers = await _firebaseService.getCustomersForStore(storeId);
        for (final c in remoteCustomers) {
          if (c.name.toLowerCase() == trimmed.toLowerCase()) {
            // Cache locally
            await _dbHelper.insertOrReplaceCustomer(c, markAsSynced: true);
            addCustomerToMemory(c);
            return c;
          }
        }
      }
    } catch (_) {}

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
      if (user.role == UserRole.storeOwner) {
        customers = await _dbHelper.getCustomersByStoreId(user.id);
        credits = await _dbHelper.getCreditsByStoreId(user.id);

        final Set<String> creditCustomerIds = credits.map((c) => c.customerId).toSet();
        final Set<String> existingCustomerIds = customers.map((c) => c.id).toSet();
        final List<String> missingCustomerIds = creditCustomerIds
            .where((id) => !existingCustomerIds.contains(id))
            .toList();

        if (missingCustomerIds.isNotEmpty) {
          final missingCustomers = await _dbHelper.getCustomersByIds(missingCustomerIds);
          customers.addAll(missingCustomers);
        }
      } else {
        customers = await _dbHelper.getAllCustomers();
        credits = await _dbHelper.getAllCredits();

        credits = credits.where((credit) => credit.customerId == user.id).toList();
        customers = customers.where((customer) => customer.id == user.id).toList();
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
    } catch (e) {
      print('Realtime sync init error: $e');
      return;
    }

    void handler(DatabaseEvent event) async {
      if (event.snapshot.value == null) return;
      
      bool changed = false;
      final creditsData = event.snapshot.value;
      
      if (creditsData is Map) {
        // Handle removed credits (check if any local credits are not in Firebase)
        final localCredits = await _dbHelper.getAllCredits();
        final firebaseCreditIds = creditsData.keys.toSet();
        
        for (final localCredit in localCredits) {
          if (user.role == UserRole.storeOwner && localCredit.storeId != user.id) continue;
          if (user.role == UserRole.customer && localCredit.customerId != user.id) continue;
          
          if (!firebaseCreditIds.contains(localCredit.id)) {
            // Credit was deleted in Firebase
            await _dbHelper.deleteCredit(localCredit.id);
            changed = true;
          }
        }
        
        // Handle added/updated credits
        for (final entry in creditsData.entries) {
          final creditId = entry.key;
          
          final credit = await _firebaseService.getCredit(creditId);
          if (credit != null) {
            await _dbHelper.insertOrReplaceCredit(credit, markAsSynced: true);
            final customer = await _firebaseService.getCustomer(credit.customerId);
            if (customer != null) {
              await _dbHelper.insertOrReplaceCustomer(customer, markAsSynced: true);
            }
            changed = true;
          }
        }
      }

      if (changed) {
        await _setStateFromDatabase(user);
      }
    }

    if (user.role == UserRole.customer) {
      _creditSubscription = _firebaseService
          .listenToCreditsForCustomer(user.id)
          .listen(handler);
    } else if (user.role == UserRole.storeOwner) {
      _creditSubscription = _firebaseService
          .listenToCreditsForStore(user.id)
          .listen(handler);
    }
  }

  Future<void> _stopRealtimeSync() async {
    await _creditSubscription?.cancel();
    _creditSubscription = null;
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
        await _firebaseService.saveCredit(credit);
        await _dbHelper.markAsSynced('credits', credit.id);
        // Mark all payments as synced too
        for (final payment in credit.payments) {
          await _dbHelper.markAsSynced('payments', payment.id);
        }
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


