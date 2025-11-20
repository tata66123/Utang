class BuildConfig {
  BuildConfig._();

  /// Set via `--dart-define=CUSTOMER_ONLY=true`
  static const bool customerOnly =
      bool.fromEnvironment('CUSTOMER_ONLY', defaultValue: false);
}

