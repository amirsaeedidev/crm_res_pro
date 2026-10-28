class SupabaseConfig {
  SupabaseConfig._();

  // This CRM is connected to the verified Food Delivery Supabase project.
  // Keep the project URL canonical so a typo in --dart-define cannot break Web MFA requests.
  // This URL is public configuration; never put a service-role/secret key in a Flutter client.
  static const url = 'https://cfdzxtnkiptnlitwvnla.supabase.co';

  static const _definedPublishableKey =
      String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  static const _legacyAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static String get publishableKey => _definedPublishableKey.isNotEmpty
      ? _definedPublishableKey
      : _legacyAnonKey;
  static const storageBucket =
      String.fromEnvironment('SUPABASE_STORAGE_BUCKET', defaultValue: 'products');
  static const categoryIconsBucket = String.fromEnvironment(
    'SUPABASE_CATEGORY_ICONS_BUCKET',
    defaultValue: 'categories',
  );
}
