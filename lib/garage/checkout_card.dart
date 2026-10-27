import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_config.dart';
import '../core/localization.dart';
import 'checkout_repository.dart';
import 'checkout_text.dart';

typedef GarageCheckoutLauncher = Future<bool> Function(Uri url);

/// QA-only owner controls. Preparing a session never opens a window or grants
/// access. A separate user gesture opens the validated link, avoiding popup
/// blockers after an async request. Keep URLs/session comparisons in memory.
class GarageSandboxCheckoutCard extends StatefulWidget {
  const GarageSandboxCheckoutCard({required this.repository,
    required this.workspaceId, required this.isOwner,
    this.openCheckout, this.onRefreshStatus, this.canPrepare, super.key});

  final GarageCheckoutRepository repository;
  final String workspaceId;
  final bool isOwner;
  final GarageCheckoutLauncher? openCheckout;
  final VoidCallback? onRefreshStatus;
  final bool Function()? canPrepare;

  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$');

  static bool available(GarageCheckoutRepository? repository,
      String? workspaceId, bool isOwner) {
    if (!isOwner || repository == null || !repository.enabled ||
        !AppConfig.isEcosystemQaBackend(repository.supabaseUrl) ||
        workspaceId == null || !_uuid.hasMatch(workspaceId)) return false;
    final actor = repository.currentUserId();
    final session = repository.currentSessionKey();
    return actor != null && _uuid.hasMatch(actor) &&
      session != null && session.isNotEmpty;
  }

  @override
  State<GarageSandboxCheckoutCard> createState() => _CheckoutCardState();
}

class _CheckoutCardState extends State<GarageSandboxCheckoutCard> {
  String _interval = 'month';
  bool _confirmed = false;
  bool _busy = false;
  bool _attempted = false;
  int _generation = 0;
  int? _message;
  Uri? _preparedUrl;
  String? _preparedActor;
  String? _preparedSession;

  bool get _available => (widget.canPrepare?.call() ?? true) &&
    GarageSandboxCheckoutCard.available(
    widget.repository, widget.workspaceId, widget.isOwner);

  bool _sameContext(GarageCheckoutRepository repository, String workspace,
      String? actor, String? session) =>
    identical(widget.repository, repository) && widget.workspaceId == workspace &&
    widget.isOwner && repository.currentUserId() == actor &&
    repository.currentSessionKey() == session && _available;

  void _discard() {
    _preparedUrl = null;
    _preparedActor = null;
    _preparedSession = null;
  }

  @override
  void didUpdateWidget(covariant GarageSandboxCheckoutCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.workspaceId != widget.workspaceId ||
        oldWidget.isOwner != widget.isOwner) {
      ++_generation;
      _discard();
      _busy = false;
      _confirmed = false;
      if (_attempted) _message = 7;
      // Never reset the attempt guard on a scope/repository replacement.
    }
  }

  @override
  void dispose() {
    ++_generation;
    _discard();
    super.dispose();
  }

  Future<void> _prepare() async {
    if (!_available || !_confirmed || _busy || _attempted) return;
    final repository = widget.repository;
    final workspace = widget.workspaceId;
    final actor = repository.currentUserId();
    final session = repository.currentSessionKey();
    final generation = _generation;
    setState(() { _busy = true; _attempted = true; _message = null; });
    GarageCheckoutResult result;
    try {
      result = await repository.start(workspaceId: workspace,
        planCode: 'garage_qa_pilot', billingInterval: _interval,
        businessPurchaseConfirmed: _confirmed);
    } catch (_) {
      result = const GarageCheckoutResult.reconciliationRequired();
    }
    if (!mounted || generation != _generation) return;
    final current = _sameContext(repository, workspace, actor, session);
    setState(() {
      _busy = false;
      if (current && result.state == GarageCheckoutState.ready && result.url != null) {
        _preparedUrl = result.url;
        _preparedActor = actor;
        _preparedSession = session;
      } else {
        _discard();
        _message = 7;
      }
    });
  }

  Future<void> _open() async {
    final url = _preparedUrl;
    if (_busy || url == null) return;
    if (!_sameContext(widget.repository, widget.workspaceId,
        _preparedActor, _preparedSession)) {
      setState(() { _discard(); _message = 7; });
      return;
    }
    final generation = _generation;
    // Single explicit navigation. Failure must not create another Checkout.
    setState(() { _busy = true; _discard(); });
    bool opened;
    try {
      opened = await (widget.openCheckout?.call(url) ?? launchUrl(url,
        mode: LaunchMode.platformDefault, webOnlyWindowName: '_self'));
    } catch (_) {
      opened = false;
    }
    if (!mounted || generation != _generation) return;
    setState(() { _busy = false; _message = opened ? 8 : 7; });
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String>(
    valueListenable: AppLocale.language,
    builder: (context, _, child) {
      if (!_available) return const SizedBox.shrink();
      final locked = _busy || _attempted;
      return Card(child: Padding(padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(GarageCheckoutText.get(0),
            style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Text(GarageCheckoutText.get(6)),
          const SizedBox(height: 12),
          Text(GarageCheckoutText.get(10)),
          DropdownButton<String>(value: _interval, isExpanded: true,
            onChanged: locked ? null : (value) {
              if (value != null) setState(() { _interval = value; _confirmed = false; });
            },
            items: [DropdownMenuItem(value: 'month',
              child: Text(GarageCheckoutText.get(1))),
              DropdownMenuItem(value: 'year',
                child: Text(GarageCheckoutText.get(2)))]),
          CheckboxListTile(contentPadding: EdgeInsets.zero,
            title: Text(GarageCheckoutText.get(3)), value: _confirmed,
            onChanged: locked ? null : (value) => setState(() { _confirmed = value == true; })),
          if (!_attempted)
            FilledButton(onPressed: _confirmed && !_busy ? _prepare : null,
              child: Text(GarageCheckoutText.get(4))),
          if (_busy) const Center(child: CircularProgressIndicator()),
          if (_preparedUrl != null)
            FilledButton(onPressed: _busy ? null : _open,
              child: Text(GarageCheckoutText.get(5))),
          if (_message != null) ...[
            const SizedBox(height: 12), Text(GarageCheckoutText.get(_message!)),
          ],
          if (widget.onRefreshStatus != null)
            TextButton(onPressed: _busy ? null : widget.onRefreshStatus,
              child: Text(GarageCheckoutText.get(9))),
        ])));
    },
  );
}
