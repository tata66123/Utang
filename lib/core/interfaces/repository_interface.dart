import '../models/models.dart';

// Abstract interface for data repositories
abstract class RepositoryInterface<T> {
  Future<void> save(T entity);
  Future<T?> getById(String id);
  Future<List<T>> getAll();
  Future<void> update(T entity);
  Future<void> delete(String id);
}

// Abstract interface for user repository
abstract class UserRepositoryInterface extends RepositoryInterface<User> {
  Future<User?> getByUsername(String username);
  Future<User?> getCurrentUser();
}

// Abstract interface for customer repository
abstract class CustomerRepositoryInterface extends RepositoryInterface<Customer> {
  Future<List<Customer>> searchByName(String name);
}

// Abstract interface for credit repository
abstract class CreditRepositoryInterface extends RepositoryInterface<CreditEntry> {
  Future<List<CreditEntry>> getByCustomerId(String customerId);
  Future<List<CreditEntry>> getOverdueCredits();
  Future<List<CreditEntry>> getDueSoonCredits();
}

// Abstract interface for payment repository
abstract class PaymentRepositoryInterface extends RepositoryInterface<Payment> {
  Future<List<Payment>> getByCreditId(String creditId);
  Future<List<Payment>> getByCustomerId(String customerId);
}
