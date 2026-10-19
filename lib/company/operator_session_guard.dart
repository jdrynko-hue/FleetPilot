import 'package:supabase_flutter/supabase_flutter.dart';

/// Prevents a privileged operator RPC result from being displayed after the
/// authenticated user or access-token session changes during the request.
///
/// This client-side check is defense in depth only. The backend must
/// independently authorize every call to the operator RPCs.
class OperatorSessionGuard {
  const OperatorSessionGuard(this.client);

  final SupabaseClient client;

  Future<T> run<T>(Future<T> Function() action) async {
    final userId = client.auth.currentUser?.id;
    final accessToken = client.auth.currentSession?.accessToken;
    if (userId == null || accessToken == null || accessToken.isEmpty) {
      throw StateError('Authenticated operator session required');
    }

    final result = await action();
    if (client.auth.currentUser?.id != userId ||
        client.auth.currentSession?.accessToken != accessToken) {
      // The RPC might already have committed. Never retry an operator decision
      // automatically; reload the current operator session first.
      throw StateError('Operator session changed during request');
    }
    return result;
  }
}
