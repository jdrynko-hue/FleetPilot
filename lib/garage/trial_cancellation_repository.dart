import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/app_config.dart';

enum GarageTrialCancellationState { disabled, unavailable, canceled, uncertain }

/// Sends only a workspace ID. Server Auth and ownership checks decide authority.
/// After a dispatched request, an uncertain response must be reconciled rather
/// than automatically retried. No response grants entitlement locally.
class GarageTrialCancellationRepository {
  GarageTrialCancellationRepository({required this.enabled,
    required this.supabaseUrl, required this.currentUserId,
    required this.currentSessionKey, required this.invoke,
    this.requestTimeout = const Duration(seconds: 12)});

  factory GarageTrialCancellationRepository.forClient(SupabaseClient client) =>
    GarageTrialCancellationRepository(
      enabled: AppConfig.garageSandboxTrialCancellationEnabled,
      supabaseUrl: AppConfig.supabaseUrl,
      currentUserId: () => client.auth.currentUser?.id,
      currentSessionKey: () => client.auth.currentSession?.accessToken,
      invoke: (body) async => (await client.functions.invoke(
        'flotaryx-garage-test-trial-cancel', body: body)).data);

  final bool enabled;
  final String supabaseUrl;
  final String? Function() currentUserId;
  final String? Function() currentSessionKey;
  final Future<Object?> Function(Map<String, Object>) invoke;
  final Duration requestTimeout;
  bool _sent = false;
  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$');

  bool available(String workspace) => enabled &&
    AppConfig.isEcosystemQaBackend(supabaseUrl) && _uuid.hasMatch(workspace) &&
    _uuid.hasMatch(currentUserId() ?? '') &&
    (currentSessionKey()?.isNotEmpty ?? false);

  Future<GarageTrialCancellationState> cancel(String workspace) async {
    if (!enabled) return GarageTrialCancellationState.disabled;
    if (!available(workspace) || requestTimeout <= Duration.zero ||
        requestTimeout > const Duration(seconds: 30)) {
      return GarageTrialCancellationState.unavailable;
    }
    if (_sent) return GarageTrialCancellationState.uncertain;
    final actor = currentUserId();
    final session = currentSessionKey();
    _sent = true;
    try {
      final raw = await invoke(Map<String, Object>.unmodifiable(
        {'workspace_id': workspace})).timeout(requestTimeout);
      if (currentUserId() != actor || currentSessionKey() != session ||
          raw is! Map || raw.length != 2 || raw['status'] != 'canceled' ||
          raw['canceled_at'] is! String ||
          DateTime.tryParse(raw['canceled_at'] as String) == null) {
        return GarageTrialCancellationState.uncertain;
      }
      return GarageTrialCancellationState.canceled;
    } catch (_) {
      return GarageTrialCancellationState.uncertain;
    }
  }
}
