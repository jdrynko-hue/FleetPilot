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

  // Independent, default-off client gate. Enabling Garage navigation or
  // entitlement reads must never implicitly enable a Checkout request.
  static const _garagePaidRejoinRequested = bool.fromEnvironment('FLOTARYX_GARAGE_SANDBOX_PAID_REJOIN_CLIENT');
  static bool get garagePaidRejoinEnabled => _garagePaidRejoinRequested && garageSandboxCheckoutUiEnabled;

  static const _garageSandboxCheckoutRequested =
      bool.fromEnvironment('FLOTARYX_GARAGE_SANDBOX_CHECKOUT_CLIENT');
  static bool garageSandboxCheckoutEnabledFor(String url,
          {required bool requested}) =>
      requested && isEcosystemQaBackend(url);
  static bool get garageSandboxCheckoutEnabled =>
      garageSandboxCheckoutEnabledFor(supabaseUrl,
          requested: _garageSandboxCheckoutRequested);

  static const _garageSandboxCheckoutUiRequested =
      bool.fromEnvironment('FLOTARYX_GARAGE_SANDBOX_CHECKOUT_UI');
  static bool garageSandboxCheckoutUiEnabledFor(String url,
      {required bool requested, required bool clientEnabled,
       required bool entitlementEnabled}) =>
      requested && clientEnabled && entitlementEnabled && isEcosystemQaBackend(url);
  static bool get garageSandboxCheckoutUiEnabled =>
      garageSandboxCheckoutUiEnabledFor(supabaseUrl,
        requested: _garageSandboxCheckoutUiRequested,
        clientEnabled: garageSandboxCheckoutEnabled,
        entitlementEnabled: garageSandboxEntitlementEnabled);

  // Independently enabled only in an exact QA build with entitlement reads.
  static const _garageTrialCancellationRequested =
      bool.fromEnvironment('FLOTARYX_GARAGE_SANDBOX_TRIAL_CANCELLATION_CLIENT');
  static bool get garageSandboxTrialCancellationEnabled =>
      _garageTrialCancellationRequested && garageSandboxEntitlementEnabled &&
      isEcosystemQaBackend(supabaseUrl);

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
