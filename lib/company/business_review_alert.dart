import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/localization.dart';
import 'business_review_console_screen.dart';
import 'operator_session_guard.dart';

typedef PendingReviewLoader = Future<int?> Function();
typedef ReviewConsoleOpener = Future<void> Function(BuildContext context);

/// Shows an operator-only shortcut and pending business verification count.
///
/// Ordinary fleet users cannot see it. The backend RPC also enforces operator
/// authorization, independent of this UI check. No emails are sent.
class BusinessReviewAlert extends StatefulWidget {
  const BusinessReviewAlert({
    super.key,
    this.loadPendingReviews,
    this.openConsole,
    this.refreshInterval = const Duration(minutes: 5),
  });

  final PendingReviewLoader? loadPendingReviews;
  final ReviewConsoleOpener? openConsole;
  final Duration refreshInterval;

  @override
  State<BusinessReviewAlert> createState() => _BusinessReviewAlertState();
}

class _BusinessReviewAlertState extends State<BusinessReviewAlert> {
  Timer? _timer;
  int? _pending;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    if (widget.refreshInterval > Duration.zero) {
      _timer = Timer.periodic(widget.refreshInterval, (_) => _refresh());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<int?> _loadFromSupabase() async {
    final client = Supabase.instance.client;
    return OperatorSessionGuard(client).run(() async {
      final userId = client.auth.currentUser!.id;

    // RLS grants access to this row only when the user is an operator.
    final operators = await client
        .from('flotaryx_verification_operators')
        .select('user_id')
        .eq('user_id', userId)
        .limit(1);
    if (operators.isEmpty) return null;

    // Use a server-side count, without downloading applicant names,
    // addresses or evidence. This also avoids the 100-row review-list cap.
    // The RPC independently enforces operator authorization.
    final pending = await client.rpc('flotaryx_operator_pending_review_count');
    if (pending is! int || pending < 0) {
      throw const FormatException('Invalid pending review count');
    }
      return pending;
    });
  }

  Future<void> _refresh() async {
    if (_loading) return;
    _loading = true;
    try {
      final pending =
          await (widget.loadPendingReviews?.call() ?? _loadFromSupabase());
      if (mounted) setState(() => _pending = pending);
    } catch (_) {
      // A permission failure or expired session must not leave a stale
      // operator shortcut on screen. The RPC also enforces authorization.
      if (mounted) setState(() => _pending = null);
    } finally {
      _loading = false;
    }
  }

  Future<void> _open() async {
    // The badge may have been visible for several minutes. Recheck current
    // operator access before navigating; a stale badge is never authority.
    if (_loading || _pending == null) return;
    _loading = true;
    try {
      final pending =
          await (widget.loadPendingReviews?.call() ?? _loadFromSupabase());
      if (!mounted) return;
      if (pending == null) {
        setState(() => _pending = null);
        return;
      }
      setState(() => _pending = pending);
    } catch (_) {
      if (mounted) setState(() => _pending = null);
      return;
    } finally {
      _loading = false;
    }
    if (!mounted) return;
    if (widget.openConsole != null) {
      await widget.openConsole!(context);
    } else {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => const BusinessReviewConsoleScreen(),
        ),
      );
    }
    if (mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (_pending == null) return const SizedBox.shrink();
    final polish = AppLocale.language.value == 'pl';
    return IconButton(
      key: const Key('business_review_alert'),
      tooltip: polish
          ? 'Weryfikacja firm — oczekujące: ${_pending!}'
          : 'Business reviews — pending: ${_pending!}',
      onPressed: _open,
      icon: Badge.count(
        count: _pending!,
        isLabelVisible: _pending! > 0,
        child: const Icon(Icons.fact_check_outlined),
      ),
    );
  }
}
