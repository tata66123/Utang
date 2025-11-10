class AppConstants {
  // App Information
  static const String appName = 'Utang App';
  static const String appVersion = '1.0.0';
  
  // Database
  static const String databaseName = 'utang_app.db';
  static const int databaseVersion = 1;
  
  // Colors
  static const int primaryColorValue = 0xFF2563EB;
  static const int successColorValue = 0xFF059669;
  static const int warningColorValue = 0xFFF59E0B;
  static const int errorColorValue = 0xFFDC2626;
  
  // Validation
  static const int minPasswordLength = 6;
  static const int minUsernameLength = 3;
  static const int minStoreNameLength = 2;
  
  // UI
  static const double defaultPadding = 16.0;
  static const double smallPadding = 8.0;
  static const double largePadding = 24.0;
  static const double borderRadius = 12.0;
  static const double smallBorderRadius = 8.0;
  
  // Notifications
  static const String reminderChannelId = 'reminders';
  static const String reminderChannelName = 'Payment Reminders';
  static const String instantChannelId = 'instant';
  static const String instantChannelName = 'Instant Notifications';
  
  // Shared Preferences Keys
  static const String themeKey = 'app_theme_mode';
  static const String userKey = 'current_user';
  static const String lastSyncKey = 'last_sync_time';
}
