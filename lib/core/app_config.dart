class AppConfig {
  static const qaAuthCallback = String.fromEnvironment('QA_AUTH_CALLBACK_URL');
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );

  // Explicit QA build opt-in; a production backend can never enable this.
  static const _ecosystemRequested = bool.fromEnvironment('FLOTARYX_ECOSYSTEM_QA');
  static bool isEcosystemQaBackend(String url) =>
      url == 'https://fyestmquqvkdebxxbcky.supabase.co';
  static bool get ecosystemQaEnabled =>
      _ecosystemRequested && isEcosystemQaBackend(supabaseUrl);

  static bool get isConfigured =>
      supabaseUrl.trim().isNotEmpty && supabasePublishableKey.trim().isNotEmpty;
}
