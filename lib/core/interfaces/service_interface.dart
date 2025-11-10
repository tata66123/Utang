import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/notification_service.dart';

// Abstract interface for authentication service
abstract class AuthServiceInterface {
  Future<User> registerUser({
    required String email,
    required String username,
    required String storeName,
    required String password,
    required UserRole role,
  });
  
  Future<bool> loginUser(String username, String password);
  Future<void> logoutUser();
  User? getCurrentUser();
  bool get isLoggedIn;
}

// Abstract interface for notification service
abstract class NotificationServiceInterface {
  Future<void> initialize();
  Future<void> showInAppNotification({
    required BuildContext context,
    required String title,
    required String message,
    NotificationType type,
  });
  Future<void> showOverdueNotification(BuildContext context);
  Future<void> showDueSoonNotification(BuildContext context, double amount);
}

// Abstract interface for sync service
abstract class SyncServiceInterface {
  Future<void> initialize();
  Future<void> syncNow();
  Stream<bool> get syncStream;
  bool get isSyncing;
  Future<Map<String, dynamic>?> getSyncStatus();
}
