import 'dart:convert';

enum UserRole { storeOwner, customer }

class User {
  User({
    required this.id, 
    required this.email, 
    required this.username, 
    required this.storeName, 
    required this.role,
    this.password,
    this.creditLimit,
  });
  final String id;
  final String email;
  final String username;
  final String storeName;
  final UserRole role;
  final String? password;
  final double? creditLimit; // Store owner's credit limit (total outstanding across all customers)

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id, 
    'email': email, 
    'username': username, 
    'storeName': storeName, 
    'role': role.name,
    'password': password,
    'creditLimit': creditLimit,
  };
  static User fromJson(Map<String, dynamic> j) => User(
    id: j['id'] as String, 
    email: j['email'] as String, 
    username: j['username'] as String, 
    storeName: j['storeName'] as String, 
    role: UserRole.values.firstWhere((e) => e.name == j['role'], orElse: () => UserRole.storeOwner),
    password: j['password'] as String?,
    creditLimit: j['creditLimit'] != null ? (j['creditLimit'] as num).toDouble() : null,
  );
}

class Customer {
  Customer({required this.id, required this.name, this.storeId, this.creditLimit});
  final String id;
  final String name;
  final String? storeId; // owning store/user id
  final double? creditLimit; // maximum borrow limit per customer

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id, 
    'name': name, 
    'storeId': storeId,
    'creditLimit': creditLimit,
  };
  static Customer fromJson(Map<String, dynamic> j) => Customer(
    id: j['id'] as String, 
    name: j['name'] as String, 
    storeId: j['storeId'] as String?,
    creditLimit: j['creditLimit'] != null ? (j['creditLimit'] as num).toDouble() : null,
  );
}

class Payment {
  Payment({required this.id, required this.amount, required this.date});
  final String id;
  final double amount;
  final DateTime date;

  Map<String, dynamic> toJson() => <String, dynamic>{'id': id, 'amount': amount, 'date': date.toIso8601String()};
  static Payment fromJson(Map<String, dynamic> j) => Payment(id: j['id'] as String, amount: (j['amount'] as num).toDouble(), date: DateTime.parse(j['date'] as String));
}

class CreditEntry {
  CreditEntry({
    required this.id, 
    required this.customerId, 
    required this.item, 
    required this.amount, 
    required this.date, 
    this.dueDate, 
    this.storeId,
    this.quantity = 1,
    this.unitPrice,
  });
  final String id;
  final String customerId;
  final String item;
  final double amount; // Total amount (unitPrice * quantity)
  final DateTime date;
  final DateTime? dueDate;
  final String? storeId; // store owner user id who created/owns the credit
  final int quantity; // Quantity of items
  final double? unitPrice; // Price per unit (optional, calculated as amount/quantity if not provided)
  final List<Payment> payments = <Payment>[];

  // Get unit price (either stored or calculated)
  double get effectiveUnitPrice => unitPrice ?? (quantity > 0 ? amount / quantity : amount);
  
  double get paidAmount => payments.fold(0.0, (double s, Payment p) => s + p.amount);
  double get balance => amount - paidAmount;
  bool get isOverdue => (dueDate != null) && balance > 0 && DateTime.now().isAfter(dueDate!);
  bool get dueSoon => (dueDate != null) && balance > 0 && dueDate!.difference(DateTime.now()).inDays <= 3 && !isOverdue;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'customerId': customerId,
    'storeId': storeId,
    'item': item,
    'amount': amount,
    'quantity': quantity,
    'unitPrice': unitPrice,
    'date': date.toIso8601String(),
    'dueDate': dueDate?.toIso8601String(),
    'payments': payments.map((Payment p) => p.toJson()).toList(),
  };

  static CreditEntry fromJson(Map<String, dynamic> j) {
    final CreditEntry e = CreditEntry(
      id: j['id'] as String,
      customerId: j['customerId'] as String,
      storeId: j['storeId'] as String?,
      item: j['item'] as String,
      amount: (j['amount'] as num).toDouble(),
      quantity: j['quantity'] != null ? (j['quantity'] as num).toInt() : 1, // Default to 1 for backward compatibility
      unitPrice: j['unitPrice'] != null ? (j['unitPrice'] as num).toDouble() : null,
      date: DateTime.parse(j['date'] as String),
      dueDate: j['dueDate'] != null ? DateTime.parse(j['dueDate'] as String) : null,
    );
    final List<dynamic> pay = j['payments'] as List<dynamic>? ?? <dynamic>[];
    e.payments.addAll(pay.map((dynamic x) => Payment.fromJson(x as Map<String, dynamic>)));
    return e;
  }
}

class AppState {
  AppState({required this.customers, required this.credits, this.currentUser});
  final List<Customer> customers;
  final List<CreditEntry> credits;
  final User? currentUser;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'customers': customers.map((Customer c) => c.toJson()).toList(),
    'credits': credits.map((CreditEntry e) => e.toJson()).toList(),
    'currentUser': currentUser?.toJson(),
  };

  static AppState fromJson(Map<String, dynamic> j) => AppState(
    customers: (j['customers'] as List<dynamic>? ?? <dynamic>[]).map((dynamic x) => Customer.fromJson(x as Map<String, dynamic>)).toList(),
    credits: (j['credits'] as List<dynamic>? ?? <dynamic>[]).map((dynamic x) => CreditEntry.fromJson(x as Map<String, dynamic>)).toList(),
    currentUser: j['currentUser'] != null ? User.fromJson(j['currentUser'] as Map<String, dynamic>) : null,
  );

  String toJsonString() => jsonEncode(toJson());
  static AppState fromJsonString(String s) => fromJson(jsonDecode(s) as Map<String, dynamic>);
}

String generateId() => DateTime.now().microsecondsSinceEpoch.toString();


