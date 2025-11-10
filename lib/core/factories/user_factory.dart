import '../models/models.dart';

/// Factory pattern for creating different types of users
abstract class UserFactory {
  static User createStoreOwner({
    required String id,
    required String email,
    required String username,
    required String storeName,
    required String password,
  }) {
    return User(
      id: id,
      email: email,
      username: username,
      storeName: storeName,
      role: UserRole.storeOwner,
      password: password,
    );
  }

  static User createCustomer({
    required String id,
    required String email,
    required String username,
    required String fullName,
    required String password,
  }) {
    return User(
      id: id,
      email: email,
      username: username,
      storeName: fullName, // For customers, storeName represents their full name
      role: UserRole.customer,
      password: password,
    );
  }

  /// Create user based on role
  static User createUser({
    required String id,
    required String email,
    required String username,
    required String name,
    required String password,
    required UserRole role,
  }) {
    switch (role) {
      case UserRole.storeOwner:
        return createStoreOwner(
          id: id,
          email: email,
          username: username,
          storeName: name,
          password: password,
        );
      case UserRole.customer:
        return createCustomer(
          id: id,
          email: email,
          username: username,
          fullName: name,
          password: password,
        );
    }
  }
}

/// Builder pattern for complex user creation
class UserBuilder {
  String? _id;
  String? _email;
  String? _username;
  String? _name;
  String? _password;
  UserRole? _role;

  UserBuilder setId(String id) {
    _id = id;
    return this;
  }

  UserBuilder setEmail(String email) {
    _email = email;
    return this;
  }

  UserBuilder setUsername(String username) {
    _username = username;
    return this;
  }

  UserBuilder setName(String name) {
    _name = name;
    return this;
  }

  UserBuilder setPassword(String password) {
    _password = password;
    return this;
  }

  UserBuilder setRole(UserRole role) {
    _role = role;
    return this;
  }

  User build() {
    if (_id == null || _email == null || _username == null || 
        _name == null || _password == null || _role == null) {
      throw ArgumentError('All user fields must be set before building');
    }

    return UserFactory.createUser(
      id: _id!,
      email: _email!,
      username: _username!,
      name: _name!,
      password: _password!,
      role: _role!,
    );
  }
}
