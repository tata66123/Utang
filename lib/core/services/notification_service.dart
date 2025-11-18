import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    // Initialize timezone
    tz.initializeTimeZones();

    // CRITICAL: Create Android notification channels for system-level notifications
    // Real devices need proper channel setup
    const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    
    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(settings);
    
    // Create notification channels for Android (system-level notifications)
    // This is critical for real devices
    final androidImplementation = _notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    
    if (androidImplementation != null) {
      // Request notification permission for Android 13+ (API 33+)
      // This is REQUIRED for real devices running Android 13+
      final granted = await androidImplementation.requestNotificationsPermission();
      if (granted == true) {
        print('Notification permission granted during initialization');
      } else {
        print('Warning: Notification permission not granted - notifications may not appear on real devices');
      }
      
      const AndroidNotificationChannel instantChannel = AndroidNotificationChannel(
        'instant',
        'Instant Notifications',
        description: 'Immediate notifications for app events',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
        showBadge: true,
      );
      
      const AndroidNotificationChannel remindersChannel = AndroidNotificationChannel(
        'reminders',
        'Payment Reminders',
        description: 'Notifications for payment due dates and reminders',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
        showBadge: true,
      );
      
      // Create channels (this is safe to call multiple times)
      await androidImplementation.createNotificationChannel(instantChannel);
      await androidImplementation.createNotificationChannel(remindersChannel);
      
      print('Notification channels created successfully for real devices');
    }
    
    _initialized = true;
  }

  Future<void> showInAppNotification({
    required BuildContext context,
    required String title,
    required String message,
    NotificationType type = NotificationType.info,
  }) async {
    // Trigger haptic feedback based on notification type
    switch (type) {
      case NotificationType.success:
        HapticFeedback.lightImpact();
        break;
      case NotificationType.warning:
        HapticFeedback.mediumImpact();
        break;
      case NotificationType.error:
        HapticFeedback.heavyImpact();
        break;
      case NotificationType.info:
        HapticFeedback.selectionClick();
        break;
    }

    // Show in-app notification using SnackBar with enhanced styling
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                _getIconForType(type),
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      message,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          backgroundColor: _getColorForType(type),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  Future<void> scheduleReminderNotification({
    required String title,
    required String message,
    required DateTime scheduledDate,
  }) async {
    await initialize();
    
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'reminders',
      'Payment Reminders',
      channelDescription: 'Notifications for payment due dates and reminders',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    
    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    
    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.zonedSchedule(
      scheduledDate.millisecondsSinceEpoch ~/ 1000,
      title,
      message,
      tz.TZDateTime.from(scheduledDate, tz.local),
      details,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  Future<void> showInstantNotification({
    required String title,
    required String message,
    NotificationType type = NotificationType.info,
  }) async {
    await initialize();
    
    // CRITICAL for real devices: Request notification permission (Android 13+)
    final androidImplementation = _notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidImplementation != null) {
      // Request permission for Android 13+ (API 33+)
      final granted = await androidImplementation.requestNotificationsPermission();
      if (granted == true) {
        print('Notification permission granted');
      } else {
        print('Notification permission denied - notifications may not appear on real devices');
      }
      
      // Ensure channel exists (recreate if needed for real devices)
      const AndroidNotificationChannel instantChannel = AndroidNotificationChannel(
        'instant',
        'Instant Notifications',
        description: 'Immediate notifications for app events',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
        showBadge: true,
      );
      await androidImplementation.createNotificationChannel(instantChannel);
    }
    
    // Enhanced Android notification details for real devices
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'instant',
      'Instant Notifications',
      channelDescription: 'Immediate notifications for app events',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      enableVibration: true,
      playSound: true,
      showWhen: true,
      autoCancel: true,
      ongoing: false,
      styleInformation: BigTextStyleInformation(''),
      category: AndroidNotificationCategory.message,
      visibility: NotificationVisibility.public,
    );
    
    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    
    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    // Use a unique ID to ensure notification shows (real devices may cache IDs)
    final notificationId = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    
    try {
      await _notifications.show(
        notificationId,
        title,
        message,
        details,
      );
      print('Notification shown successfully: $title - $message (ID: $notificationId)');
    } catch (e) {
      print('Error showing notification: $e');
      // Retry once after a short delay (real devices sometimes need this)
      await Future.delayed(const Duration(milliseconds: 100));
      try {
        await _notifications.show(
          notificationId + 1,
          title,
          message,
          details,
        );
        print('Notification shown on retry: $title - $message');
      } catch (e2) {
        print('Error showing notification on retry: $e2');
      }
    }
  }

  IconData _getIconForType(NotificationType type) {
    switch (type) {
      case NotificationType.success:
        return Icons.check_circle;
      case NotificationType.warning:
        return Icons.warning;
      case NotificationType.error:
        return Icons.error;
      case NotificationType.info:
        return Icons.info;
    }
  }

  Color _getColorForType(NotificationType type) {
    switch (type) {
      case NotificationType.success:
        return Colors.green;
      case NotificationType.warning:
        return Colors.orange;
      case NotificationType.error:
        return Colors.red;
      case NotificationType.info:
        return Colors.blue;
    }
  }

  Future<void> cancelAllNotifications() async {
    await _notifications.cancelAll();
  }

  Future<void> cancelNotification(int id) async {
    await _notifications.cancel(id);
  }

  // Specific notification methods for customer dashboard
  Future<void> showCreditAddedNotification(BuildContext context, String storeName, double amount) async {
    await showInAppNotification(
      context: context,
      title: 'Credit Added',
      message: '₱${amount.toStringAsFixed(2)} credit added by $storeName.',
      type: NotificationType.info,
    );
  }

  Future<void> showPaymentRecordedNotification(BuildContext context, String storeName, double amount) async {
    await showInAppNotification(
      context: context,
      title: 'Payment Recorded',
      message: '₱${amount.toStringAsFixed(2)} payment recorded for your credit from $storeName.',
      type: NotificationType.success,
    );
  }

  Future<void> showDueSoonNotification(BuildContext context, double amount) async {
    await showInAppNotification(
      context: context,
      title: 'Due Soon',
      message: 'Your ₱${amount.toStringAsFixed(2)} credit is due tomorrow.',
      type: NotificationType.warning,
    );
  }

  Future<void> showOverdueNotification(BuildContext context) async {
    await showInAppNotification(
      context: context,
      title: 'Overdue Alert',
      message: 'Your credit is overdue!',
      type: NotificationType.error,
    );
  }
}

enum NotificationType {
  success,
  warning,
  error,
  info,
}
