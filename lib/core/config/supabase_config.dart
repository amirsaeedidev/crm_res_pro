class SupabaseConfig {
  SupabaseConfig._();

  // Public project URL. Never put a service-role/secret key in a Flutter client.
  static const url = 'https://cfdzxtnkiptnlitwvnla.supabase.co';

  static const _definedPublishableKey =
      String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  static const _legacyAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const _genericPublicKey = String.fromEnvironment('SUPABASE_KEY');

  // New Supabase publishable keys are preferred, while older deployments that
  // still inject SUPABASE_ANON_KEY remain compatible.
  static String get publishableKey {
    for (final candidate in [
      _definedPublishableKey,
      _legacyAnonKey,
      _genericPublicKey,
    ]) {
      final value = candidate.trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  static const storageBucket = String.fromEnvironment(
    'SUPABASE_STORAGE_BUCKET',
    defaultValue: 'products',
  );

  static const categoryIconsBucket = String.fromEnvironment(
    'SUPABASE_CATEGORY_ICONS_BUCKET',
    defaultValue: 'categories',
  );
}
