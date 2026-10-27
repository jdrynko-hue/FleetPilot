import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_config.dart';

enum GarageCheckoutState { disabled, unavailable, ready, reconciliationRequired }

/// A validated navigation destination, never evidence of trial/paid access.
/// Do not log or persist the session URL. Access still comes from entitlement.
class GarageCheckoutResult {
  const GarageCheckoutResult._(this.state, this.url);
  const GarageCheckoutResult.disabled()
      : this._(GarageCheckoutState.disabled, null);
  const GarageCheckoutResult.unavailable()
      : this._(GarageCheckoutState.unavailable, null);
  const GarageCheckoutResult.reconciliationRequired()
      : this._(GarageCheckoutState.reconciliationRequired, null);

  final GarageCheckoutState state;
  final Uri? url;

  static GarageCheckoutResult parse(Object? raw, {int trialDays = 7}) {
    const fields = {'mode', 'session_id', 'url', 'trial_days'};
    if (raw is! Map || raw.length != fields.length ||
        raw.keys.any((key) => !fields.contains(key)) ||
        raw['mode'] != 'test' || raw['trial_days'] is! int ||
        !{0, 7}.contains(trialDays) || raw['trial_days'] != trialDays || raw['session_id'] is! String ||
        !RegExp(r'^cs_test_[A-Za-z0-9]+$').hasMatch(raw['session_id'] as String) ||
        raw['url'] is! String) {
      throw const FormatException('Invalid Garage Checkout response');
    }
    final value = raw['url'] as String;
    final uri = Uri.tryParse(value);
    if (value.length > 8192 || RegExp(r'[\s\\]').hasMatch(value) ||
        uri == null || uri.scheme != 'https' ||
        uri.host != 'checkout.stripe.com' || uri.port != 443 ||
        uri.userInfo.isNotEmpty ||
        uri.path != '/c/pay/${raw['session_id']}' ||
        !value.startsWith('https://checkout.stripe.com/')) {
      throw const FormatException('Invalid Garage Checkout response');
    }
    return GarageCheckoutResult._(GarageCheckoutState.ready, uri);
  }
}

typedef GarageCheckoutInvoke = Future<Object?> Function(Map<String, Object> body);

/// Explicit single-attempt adapter for the owner-only server Checkout endpoint.
/// Server Auth + the private billing resolver decide ownership, catalog,
/// currency, price and trial eligibility; client role claims cannot grant them.
///
/// After sending any request, a second start on this instance is refused.
/// Timeout/error/session replacement may mean Stripe already created a session.
/// Reconcile on the server instead of retrying automatically, switching plans,
/// or returning an old URL. This client guard supplements the durable ledger;
/// it is not a cross-tab or persistent idempotency mechanism.
class GarageCheckoutRepository {
  GarageCheckoutRepository({required this.enabled, required this.supabaseUrl,
    required this.currentUserId, required this.currentSessionKey,
    required this.invoke, this.paidRejoinEnabled = false, this.requestTimeout = const Duration(seconds: 12)});

  factory GarageCheckoutRepository.forClient(SupabaseClient client) =>
      GarageCheckoutRepository(
        enabled: AppConfig.garageSandboxCheckoutEnabled,
        paidRejoinEnabled: AppConfig.garagePaidRejoinEnabled,
        supabaseUrl: AppConfig.supabaseUrl,
        currentUserId: () => client.auth.currentUser?.id,
        currentSessionKey: () => client.auth.currentSession?.accessToken,
        invoke: (body) async => (await client.functions.invoke(
          'flotaryx-garage-test-checkout', body: body)).data,
      );

  final bool enabled;
  final bool paidRejoinEnabled;
  final String supabaseUrl;
  final String? Function() currentUserId;
  // Memory-only equality check; never decode, log, persist or include in JSON.
  final String? Function() currentSessionKey;
  final GarageCheckoutInvoke invoke;
  final Duration requestTimeout;
  bool _requestSent = false;

  static final _uuid = RegExp(
      r'^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$');
  static final _plan = RegExp(r'^[a-z][a-z0-9_]{1,31}$');

  Future<GarageCheckoutResult> start({required String workspaceId,
      required String planCode, required String billingInterval,
      required bool businessPurchaseConfirmed, bool paidRejoin = false}) async {
    if (!enabled) return const GarageCheckoutResult.disabled();
    if ((paidRejoin && !paidRejoinEnabled) || !AppConfig.isEcosystemQaBackend(supabaseUrl) ||
        !_uuid.hasMatch(workspaceId) || !_plan.hasMatch(planCode) ||
        !{'month', 'year'}.contains(billingInterval) ||
        !businessPurchaseConfirmed || requestTimeout <= Duration.zero ||
        requestTimeout > const Duration(seconds: 30)) {
      return const GarageCheckoutResult.unavailable();
    }
    final actor = currentUserId();
    final session = currentSessionKey();
    if (actor == null || !_uuid.hasMatch(actor) ||
        session == null || session.isEmpty) {
      return const GarageCheckoutResult.unavailable();
    }
    if (_requestSent) {
      return const GarageCheckoutResult.reconciliationRequired();
    }
    // Set synchronously before the first await, including synchronous invoke
    // failures. Never reset after an uncertain result or after returning a URL.
    _requestSent = true;
    try {
      final raw = await invoke(Map<String, Object>.unmodifiable({
        'workspace_id': workspaceId,
        'plan_code': planCode,
        'billing_interval': billingInterval,
        'business_purchase_confirmed': true,
        if (paidRejoin) 'purchase_kind': 'paid_rejoin',
      })).timeout(requestTimeout);
      if (currentUserId() != actor || currentSessionKey() != session) {
        return const GarageCheckoutResult.reconciliationRequired();
      }
      return GarageCheckoutResult.parse(raw, trialDays: paidRejoin ? 0 : 7);
    } catch (_) {
      // Never surface raw SDK exceptions, tokens, customer data or URLs.
      return const GarageCheckoutResult.reconciliationRequired();
    }
  }
}
