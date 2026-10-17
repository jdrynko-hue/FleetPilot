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

  // Production is a separate explicit build opt-in after backend installation.
  // Neither flag can connect the ecosystem to an arbitrary backend.
  static const _productionRequested =
      bool.fromEnvironment('FLOTARYX_ECOSYSTEM_PRODUCTION');
  static bool ecosystemEnabledFor(String url, {bool qa = false, bool production = false}) =>
      (qa && isEcosystemQaBackend(url)) ||
      (production && url == 'https://wqhymmtiawfwjikdaujo.supabase.co');
  static bool get ecosystemEnabled => ecosystemEnabledFor(supabaseUrl,
      qa: _ecosystemRequested, production: _productionRequested);

  static bool get isConfigured =>
      supabaseUrl.trim().isNotEmpty && supabasePublishableKey.trim().isNotEmpty;
}
