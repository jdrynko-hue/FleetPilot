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

  // This read path is independent from the general Garage QA navigation flag.
  // It stays off until the private ledger and entitlement Edge Function have
  // both been reviewed and installed in the isolated QA project.
  static const _garageSandboxEntitlementRequested =
      bool.fromEnvironment('FLOTARYX_GARAGE_SANDBOX_ENTITLEMENT');
  static bool garageSandboxEntitlementEnabledFor(String url,
          {required bool requested}) =>
      requested && isEcosystemQaBackend(url);
  static bool get garageSandboxEntitlementEnabled =>
      garageSandboxEntitlementEnabledFor(supabaseUrl,
          requested: _garageSandboxEntitlementRequested);

  // Production is a separate explicit build opt-in after backend installation.
  // Neither flag can connect the ecosystem to an arbitrary backend.
  static const _productionRequested =
      bool.fromEnvironment('FLOTARYX_ECOSYSTEM_PRODUCTION');
  static bool ecosystemEnabledFor(String url, {bool qa = false, bool production = false}) =>
      (qa && isEcosystemQaBackend(url)) ||
      (production && url == 'https://wqhymmtiawfwjikdaujo.supabase.co');
  static bool get ecosystemEnabled => ecosystemEnabledFor(supabaseUrl,
      qa: _ecosystemRequested, production: _productionRequested);

  // Smart Maintenance remains QA-only until its server-side RLS and RPCs
  // have been reviewed and enabled. No production URL can turn it on.
  static const _smartMaintenanceRequested =
      bool.fromEnvironment('FLOTARYX_SMART_MAINTENANCE_QA');
  static bool smartMaintenanceQaEnabledFor(String url,
          {required bool requested}) =>
      requested && isEcosystemQaBackend(url);
  static bool get smartMaintenanceQaEnabled =>
      smartMaintenanceQaEnabledFor(supabaseUrl,
          requested: _smartMaintenanceRequested);

  static bool get isConfigured =>
      supabaseUrl.trim().isNotEmpty && supabasePublishableKey.trim().isNotEmpty;
}
