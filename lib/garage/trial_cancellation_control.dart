import 'package:flutter/material.dart';
import '../core/localization.dart';
import 'trial_cancellation_repository.dart';

/// Shown only inside a current server-confirmed owner trial. Recheck the same
/// actor/session/workshop after the confirmation dialog and async request.
class GarageTrialCancellationControl extends StatefulWidget {
  const GarageTrialCancellationControl({required this.repository,
    required this.workspaceId, required this.trialEndsAt,
    required this.onRefresh, this.canCancel, super.key});
  final GarageTrialCancellationRepository repository;
  final String workspaceId;
  final DateTime trialEndsAt;
  final VoidCallback onRefresh;
  final bool Function()? canCancel;
  @override
  State<GarageTrialCancellationControl> createState() => _CancellationState();
}

class _CancellationState extends State<GarageTrialCancellationControl> {
  bool _busy = false;
  bool _attempted = false;
  String? _message;
  String text(String en, String pl) => AppLocale.language.value == 'pl' ? pl : en;
  bool get _available => (widget.canCancel?.call() ?? true) &&
    widget.repository.available(widget.workspaceId) &&
    widget.trialEndsAt.isAfter(DateTime.now().toUtc());

  Future<void> _cancel() async {
    if (_busy || _attempted || !_available) return;
    final repository = widget.repository;
    final workspace = widget.workspaceId;
    final actor = repository.currentUserId();
    final session = repository.currentSessionKey();
    final end = widget.trialEndsAt;
    bool sameContext() => mounted && identical(widget.repository, repository) &&
      widget.workspaceId == workspace && widget.trialEndsAt == end &&
      repository.currentUserId() == actor && repository.currentSessionKey() == session &&
      _available;
    setState(() => _busy = true);
    final confirmed = await showDialog<bool>(context: context, builder: (context) =>
      AlertDialog(title: Text(text('Cancel test trial?', 'Anulować testowy trial?')),
        content: Text(text(
          'Trial access ends immediately. This test subscription will not renew or charge after the trial. This cannot start another free trial.',
          'Dostęp próbny zakończy się natychmiast. Ta testowa subskrypcja nie odnowi się ani nie pobierze opłaty po trialu. Anulowanie nie umożliwia kolejnego darmowego trialu.')),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false),
          child: Text(text('Keep trial', 'Zachowaj trial'))),
          FilledButton(onPressed: () => Navigator.pop(context, true),
            child: Text(text('Cancel test trial', 'Anuluj testowy trial')))]));
    if (!sameContext()) { if (mounted) setState(() => _busy = false); return; }
    if (confirmed != true) { setState(() => _busy = false); return; }
    setState(() => _attempted = true);
    final result = await repository.cancel(workspace);
    if (!sameContext()) { if (mounted) setState(() => _busy = false); return; }
    setState(() {
      _busy = false;
      _message = result == GarageTrialCancellationState.canceled
        ? text('Cancellation confirmed. Refreshing access status.',
            'Anulowanie potwierdzone. Odświeżam status dostępu.')
        : text('Cancellation could not be confirmed. Refresh the status before taking further action.',
            'Nie udało się potwierdzić anulowania. Odśwież status przed dalszym działaniem.');
    });
    if (result == GarageTrialCancellationState.canceled) widget.onRefresh();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start, children: [
      OutlinedButton(onPressed: _available && !_busy && !_attempted ? _cancel : null,
        child: Text(_busy ? text('Checking…', 'Sprawdzam…') :
          text('Cancel test trial', 'Anuluj testowy trial'))),
      if (_message != null) ...[
        Text(_message!, semanticsLabel: _message),
        TextButton(onPressed: _busy ? null : widget.onRefresh,
          child: Text(text('Refresh subscription status', 'Odśwież status subskrypcji'))),
      ],
    ]);
}
