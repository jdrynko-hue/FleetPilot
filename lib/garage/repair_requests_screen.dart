import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/localization.dart';
import 'repair_bridge_repository.dart';
import 'customer_quote_screen.dart';
import 'order_actions_repository.dart';
import 'resource_calendar_repository.dart';
import 'garage_ui_text.dart';

/// QA module only. The RPC checks current membership and active connections.
class GarageRepairRequestsScreen extends StatefulWidget {
  const GarageRepairRequestsScreen({required this.load, this.loadDetail, this.accept, this.approve, this.progress, this.advance, this.loadMechanics, this.assign, super.key});

  factory GarageRepairRequestsScreen.forClient({
    required SupabaseClient client, required String workspaceId, bool fleet = false, bool canAssign = false,
  }) {
    final user = client.auth.currentUser?.id;
    final repository = GarageRepairBridgeRepository(client);
    final actions = GarageOrderActionsRepository(client);
    void checkAccount() {
      if (user == null || client.auth.currentUser?.id != user) {
        throw StateError('Account changed');
      }
    }
    return GarageRepairRequestsScreen(
      load: () async {
        checkAccount();
        final rows = fleet ? await repository.fleetRequests(workspaceId)
          : await repository.requests(workspaceId);
        checkAccount();
        return rows;
      },
      loadDetail: (row) async {
        checkAccount();
        final data = await repository.load(row.id);
        checkAccount();
        return data;
      },
      accept: fleet ? null : (row) async {
        checkAccount();
        final id = await repository.acceptRepairRequest(row.id);
        checkAccount();
        return id;
      },
      approve: !fleet ? null : (row, revision) async {
        checkAccount();
        final value = await repository.approveQuote(row.id, revision);
        checkAccount();
        return value;
      },
      advance: fleet ? null : (snapshot, target) async {
        checkAccount();
        final value = await actions.advance(snapshot.workspaceId, snapshot.workOrderId!, target);
        checkAccount();
        return value;
      },
      loadMechanics: fleet || !canAssign ? null : () async {
        checkAccount();
        final rows = await GarageResourceCalendarRepository(client).mechanics(workspaceId);
        checkAccount();
        return rows;
      },
      assign: fleet || !canAssign ? null : (snapshot, mechanic) async {
        checkAccount();
        final value = await actions.assign(snapshot.workspaceId, snapshot.workOrderId!, mechanic);
        checkAccount();
        return value;
      },
      progress: fleet ? null : (row, status) async {
        checkAccount();
        final value = await repository.updateProgress(row.id, status);
        checkAccount();
        return value;
      },
    );
  }

  final Future<List<GarageRepairRequest>> Function() load;
  final Future<GarageRepairBridgeSnapshot> Function(GarageRepairRequest)? loadDetail;
  final Future<String> Function(GarageRepairRequest)? accept;
  final Future<int> Function(GarageRepairRequest, int)? approve;
  final Future<String> Function(GarageRepairRequest, String)? progress;
  final Future<String> Function(GarageRepairBridgeSnapshot, String)? advance;
  final Future<List<GarageRosterMechanic>> Function()? loadMechanics;
  final Future<String> Function(GarageRepairBridgeSnapshot, String)? assign;

  @override
  State<GarageRepairRequestsScreen> createState() => _RepairRequestsState();
}

class _RepairRequestsState extends State<GarageRepairRequestsScreen> {
  List<GarageRepairRequest> _rows = const [];
  bool _loading = true;
  bool _failed = false;
  int _generation = 0;
  String _tr(String pl, String en) =>
      AppLocale.language.value == 'pl' ? pl : en;

  @override
  void initState() { super.initState(); _refresh(); }

  @override
  void didUpdateWidget(covariant GarageRepairRequestsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.load != widget.load) _refresh();
  }

  Future<void> _refresh() async {
    final generation = ++_generation;
    setState(() { _loading = true; _failed = false; _rows = const []; });
    try {
      final rows = await widget.load();
      if (!mounted || generation != _generation) return;
      setState(() { _rows = List.unmodifiable(rows); _loading = false; });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() { _failed = true; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_tr('Naprawy Fleet ↔ Garage', 'Fleet ↔ Garage repairs')),
      actions: [IconButton(
        tooltip: GarageUiText.get('refresh'),
        onPressed: _loading ? null : _refresh,
        icon: const Icon(Icons.refresh),
      )],
    ),
    body: SafeArea(child: _loading
      ? const Center(child: CircularProgressIndicator())
      : ListView(padding: const EdgeInsets.all(16), children: [
          if (_failed) ...[
            Text(_tr('Nie udało się pobrać zgłoszeń. Sprawdź uprawnienia.',
                'Could not load requests. Verify your access.')),
            TextButton(onPressed: _refresh,
              child: Text(_tr('Spróbuj ponownie', 'Try again'))),
          ] else if (_rows.isEmpty)
            Text(_tr('Brak zgłoszeń napraw dla wybranego konta.',
                'No repair requests for this account scope.')),
          for (final row in _rows)
            Card(child: ListTile(
              onTap: widget.loadDetail == null ? null : () async {
                await Navigator.of(context).push<void>(MaterialPageRoute(
                  builder: (_) => GarageRepairRequestDetailScreen(
                    request: row, load: () => widget.loadDetail!(row),
                    accept: widget.accept == null ? null : () => widget.accept!(row),
                    approve: widget.approve == null ? null : (revision) => widget.approve!(row, revision),
                    progress: widget.progress == null ? null : (status) => widget.progress!(row, status),
                    advance: widget.advance,
                    loadMechanics: widget.loadMechanics,
                    assign: widget.assign,
                  ),
                ));
                if (mounted) _refresh();
              },
              trailing: widget.loadDetail == null ? null : const Icon(Icons.chevron_right),
              title: Text(row.title),
              subtitle: Text(row.status == 'sent'
                ? _tr('Oczekuje na przyjęcie', 'Awaiting workshop acceptance')
                : _tr('Przyjęte przez warsztat', 'Accepted by workshop')),
            )),
        ])),
  );
}

class GarageRepairRequestDetailScreen extends StatefulWidget {
  const GarageRepairRequestDetailScreen({required this.request,
    required this.load, this.accept, this.approve, this.progress, this.advance, this.loadMechanics, this.assign, super.key});
  final GarageRepairRequest request;
  final Future<GarageRepairBridgeSnapshot> Function() load;
  final Future<String> Function()? accept;
  final Future<int> Function(int)? approve;
  final Future<String> Function(String)? progress;
  final Future<String> Function(GarageRepairBridgeSnapshot, String)? advance;
  final Future<List<GarageRosterMechanic>> Function()? loadMechanics;
  final Future<String> Function(GarageRepairBridgeSnapshot, String)? assign;
  @override
  State<GarageRepairRequestDetailScreen> createState() => _RepairDetailState();
}

class _RepairDetailState extends State<GarageRepairRequestDetailScreen> {
  GarageRepairBridgeSnapshot? _snapshot;
  String? _assignedEmail;
  bool _busy = true;
  String? _error;
  int _generation = 0;
  String _tr(String pl, String en) => AppLocale.language.value == 'pl' ? pl : en;
  @override
  void initState() { super.initState(); _refresh(); }
  @override
  void didUpdateWidget(covariant GarageRepairRequestDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.request != oldWidget.request || widget.load != oldWidget.load) _refresh();
  }

  Future<GarageRepairBridgeSnapshot> _loadScoped() async {
    final row = widget.request;
    final data = await widget.load();
    if (data.requestId != row.id || data.workspaceId != row.workspaceId ||
        data.companyId != row.companyId) {
      throw const FormatException('Repair scope changed');
    }
    return data;
  }

  Future<void> _refresh() async {
    final generation = ++_generation;
    setState(() { _busy = true; _snapshot = null; _assignedEmail = null; _error = null; });
    try {
      final data = await _loadScoped();
      if (mounted && generation == _generation) {
        // The server-authorized repair snapshot is ready to act on now.
        // Optional roster enrichment must never keep status actions disabled.
        setState(() { _snapshot = data; _busy = false; });
      }
      // Staff contact is resolved only against the authorized workshop roster.
      // Failed roster lookups never expose the ID or block the repair itself.
      if (data.mechanicUserId != null && widget.loadMechanics != null) {
        try {
          final roster = await widget.loadMechanics!();
          final matching = roster.where((m) =>
              m.userId == data.mechanicUserId).toList();
          if (mounted && generation == _generation &&
              matching.length == 1) {
            setState(() => _assignedEmail = matching.single.email);
          }
        } catch (_) {
          // Keep the assignment boolean without showing private contacts.
        }
      }
    } catch (_) {
      if (mounted && generation == _generation) setState(() => _error = _tr(
        'Nie udało się pobrać zgłoszenia. Sprawdź dostęp i odśwież.',
        'Could not load the request. Verify access and refresh.'));
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _accept() async {
    if (_busy || widget.accept == null || _snapshot?.status != 'sent') return;
    // Lock before opening the dialog, including against repeated taps.
    setState(() => _busy = true);
    final generation = _generation;
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: Text(_tr('Przyjąć naprawę?', 'Accept this repair?')),
      content: Text(_tr('Powstanie zlecenie warsztatowe. Kosztorys wymaga osobnej zgody floty.',
        'This creates a workshop work order. The estimate needs separate fleet approval.')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false),
          child: Text(_tr('Anuluj', 'Cancel'))),
        FilledButton(onPressed: () => Navigator.pop(context, true),
          child: Text(_tr('Przyjmij', 'Accept'))),
      ],
    ));
    if (!mounted || generation != _generation) return;
    if (confirmed != true) { setState(() => _busy = false); return; }
    try {
      // Recheck scope, consent and status immediately before writing.
      final latest = await _loadScoped();
      if (!mounted || generation != _generation) return;
      if (latest.status == 'sent') await widget.accept!();
      if (!mounted || generation != _generation) return;
      await _refresh();
    } catch (_) {
      if (!mounted || generation != _generation) return;
      // A timeout may follow a successful write. Require read-back, never retry it automatically.
      setState(() {
        _snapshot = null; _busy = false;
        _error = _tr('Nie potwierdzono przyjęcia. Odśwież, aby sprawdzić aktualny stan.',
          'Acceptance was not confirmed. Refresh to check the current status.');
      });
    }
  }

  static List<String> nextStatuses(String? status) => switch (status) {
    'in_progress' => ['awaiting_parts', 'ready'],
    'awaiting_parts' => ['in_progress', 'ready'],
    'ready' => ['collected'],
    _ => [],
  };

  String _status(String status) => switch (status) {
    'received' => GarageUiText.get('received'),
    'diagnosing' => GarageUiText.get('diagnosing'),
    'awaiting_approval' => GarageUiText.get('awaitingApproval'),
    'awaiting_parts' => GarageUiText.get('awaitingParts'),
    'in_progress' => GarageUiText.get('inProgress'),
    'ready' => GarageUiText.get('readyCollection'),
    'collected' => GarageUiText.get('collected'),
    'cancelled' => GarageUiText.get('cancelled'),
    _ => status,
  };

  Future<void> _updateProgress(String target) async {
    if (_busy || widget.progress == null ||
        !nextStatuses(_snapshot?.workOrderStatus).contains(target)) return;
    final previous = _snapshot!.workOrderStatus;
    setState(() => _busy = true);
    final generation = _generation;
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: Text(_tr('Zmień status naprawy', 'Update repair status')),
      content: Text(_status(target)),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false),
        child: Text(_tr('Anuluj', 'Cancel'))),
        FilledButton(onPressed: () => Navigator.pop(context, true),
          child: Text(_tr('Potwierdź', 'Confirm')))],
    ));
    if (!mounted || generation != _generation) return;
    if (confirmed != true) { setState(() => _busy = false); return; }
    try {
      final latest = await _loadScoped();
      if (!mounted || generation != _generation) return;
      if (latest.workOrderStatus != previous ||
          !nextStatuses(latest.workOrderStatus).contains(target)) {
        await _refresh();
        return;
      }
      final result = await widget.progress!(target);
      if (result != target) throw const FormatException('Unexpected repair status');
      if (mounted && generation == _generation) await _refresh();
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() { _snapshot = null; _busy = false;
        _error = _tr('Nie potwierdzono statusu. Odśwież przed kolejną zmianą.',
          'Status was not confirmed. Refresh before another change.'); });
    }
  }

  bool _canAdvance(GarageRepairBridgeSnapshot data, String target) =>
      data.status == 'accepted' && data.workOrderId != null &&
      (target == 'diagnosing' ? data.workOrderStatus == 'received' :
        target == 'in_progress' && data.workOrderStatus == 'awaiting_approval' &&
          data.quote?.approved == true);

  Future<void> _advance(String target) async {
    if (_busy || widget.advance == null || _snapshot == null ||
        !_canAdvance(_snapshot!, target)) return;
    setState(() => _busy = true);
    final generation = _generation;
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: Text(target == 'diagnosing' ? _tr('Rozpocznij diagnostykę', 'Begin diagnosis')
        : _tr('Rozpocznij naprawę', 'Start approved repair')),
      content: Text(target == 'diagnosing'
        ? _tr('Diagnostyka umożliwi przygotowanie kosztorysu.', 'Diagnosis enables estimate preparation.')
        : _tr('Wymagana jest zgoda na aktualny kosztorys i przypisany mechanik.',
            'Current estimate approval and an assigned mechanic are required.')),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: Text(_tr('Anuluj', 'Cancel'))),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(_tr('Potwierdź', 'Confirm')))],
    ));
    if (!mounted || generation != _generation) return;
    if (confirmed != true) { setState(() => _busy = false); return; }
    try {
      final data = await _loadScoped();
      if (!mounted || generation != _generation) return;
      if (_canAdvance(data, target)) {
        final result = await widget.advance!(data, target);
        if (result != target) throw const FormatException('Unexpected repair status');
      }
      if (mounted && generation == _generation) await _refresh();
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() { _snapshot = null; _busy = false;
        _error = _tr('Nie potwierdzono operacji. Sprawdź przypisanie mechanika i odśwież.',
          'Operation was not confirmed. Check mechanic assignment and refresh.'); });
    }
  }

  Future<void> _assign() async {
    if (_busy || widget.assign == null || widget.loadMechanics == null) return;
    setState(() => _busy = true);
    final generation = _generation;
    try {
      final mechanics = await widget.loadMechanics!();
      if (!mounted || generation != _generation) return;
      String? selected;
      final mechanic = await showDialog<String>(context: context, builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(_tr('Przypisz mechanika', 'Assign mechanic')),
          content: SizedBox(width: 320, child: mechanics.isEmpty
            ? Text(_tr('Brak potwierdzonych kont mechaników.', 'No verified mechanic accounts.'))
            : DropdownButtonFormField<String>(
              isExpanded: true, initialValue: selected,
              decoration: InputDecoration(labelText: _tr('Mechanik', 'Mechanic')),
              items: [for (final item in mechanics) DropdownMenuItem(value: item.userId,
                child: Text(item.email, overflow: TextOverflow.ellipsis))],
              onChanged: (value) => update(() => selected = value),
            )),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(_tr('Anuluj', 'Cancel'))),
            FilledButton(onPressed: selected == null ? null : () => Navigator.pop(context, selected),
              child: Text(_tr('Przypisz', 'Assign')))],
        ),
      ));
      if (!mounted || generation != _generation) return;
      if (mechanic == null) { setState(() => _busy = false); return; }
      if (!mechanics.any((row) => row.userId == mechanic)) throw const FormatException('Invalid mechanic');
      final latest = await _loadScoped();
      if (!mounted || generation != _generation) return;
      if (latest.status != 'accepted' || latest.workOrderId == null ||
          const {'collected', 'cancelled'}.contains(latest.workOrderStatus)) {
        await _refresh(); return;
      }
      final result = await widget.assign!(latest, mechanic);
      if (result != mechanic) throw const FormatException('Unexpected mechanic');
      if (mounted && generation == _generation) await _refresh();
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() { _snapshot = null; _busy = false;
        _error = _tr('Nie potwierdzono przypisania. Odśwież przed kolejną próbą.',
          'Assignment was not confirmed. Refresh before trying again.'); });
    }
  }

  Future<void> _openQuote() async {
    if (_busy || widget.approve == null || !_snapshot!.needsFleetApproval) return;
    setState(() => _busy = true);
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => GarageCustomerQuoteScreen(
      loadQuote: () async {
        final data = await _loadScoped();
        return data.workOrderStatus == 'awaiting_approval' ? data.quote : null;
      },
      approveRevision: widget.approve!,
    )));
    if (mounted) await _refresh();
  }

  String _eventLabel(GarageRepairBridgeEvent event) => switch (event.action) {
    'request_sent' => GarageUiText.get('requestSent'),
    'request_accepted' => GarageUiText.get('workshopAccepted'),
    'quote_approved' => GarageUiText.get('estimateApproved'),
    'progress_updated' => GarageUiText.get('repairStatusChanged'),
    'connection_revoked' => GarageUiText.get('connectionRevoked'),
    _ => GarageUiText.get('event'),
  };

  String? _eventDescription(GarageRepairBridgeEvent event) {
    if (event.action == 'quote_approved') {
      return '${GarageUiText.get('estimateRevision')}: '
          '${event.details['revision']}';
    }
    if (event.action == 'progress_updated') {
      return '${_status(event.details['from'] as String)} → '
          '${_status(event.details['to'] as String)}';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final data = _snapshot;
    return Scaffold(
      appBar: AppBar(title: Text(GarageUiText.get('repairRequest')),
        actions: [IconButton(tooltip: GarageUiText.get('refresh'),
          onPressed: _busy ? null : _refresh, icon: const Icon(Icons.refresh))]),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: [
        if (_busy && data == null) const Center(child: CircularProgressIndicator()),
        if (_error != null) ...[
          Text(_error!),
          TextButton(onPressed: _busy ? null : _refresh,
            child: Text(GarageUiText.get('refresh'))),
        ],
        if (data != null) ...[
          Text(data.title, style: Theme.of(context).textTheme.titleLarge),
          Text(data.status == 'sent' ? _tr('Oczekuje na przyjęcie', 'Awaiting acceptance')
            : _tr('Przyjęte przez warsztat', 'Accepted by workshop')),
          if (data.sharedDescription != null) Text(data.sharedDescription!),
          if (data.sharedRegistration != null) Text(data.sharedRegistration!),
          if (data.status == 'sent' && widget.accept != null)
            FilledButton(key: const Key('repair_accept'), onPressed: _busy ? null : _accept,
              child: Text(_tr('Przyjmij naprawę', 'Accept repair'))),
          if (data.workOrderStatus != null) Text(_status(data.workOrderStatus!),
            key: const Key('repair_current_status')),
          if (data.mechanicAssigned != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              key: const Key('repair_assigned_mechanic'),
              leading: const Icon(Icons.engineering_outlined),
              title: Text(GarageUiText.get('assignedMechanic')),
              subtitle: Text(data.mechanicAssigned!
                ? (_assignedEmail ?? GarageUiText.get('mechanicAssigned'))
                : GarageUiText.get('notAssigned')),
            ),
          if (widget.approve != null && data.needsFleetApproval)
            FilledButton(key: const Key('repair_review_quote'), onPressed: _busy ? null : _openQuote,
              child: Text(_tr('Sprawdź i zatwierdź kosztorys', 'Review and approve estimate'))),
          if (widget.advance != null)
            for (final target in ['diagnosing', 'in_progress'])
              if (_canAdvance(data, target))
                FilledButton(key: Key('repair_advance_$target'), onPressed: _busy ? null : () => _advance(target),
                  child: Text(target == 'diagnosing' ? _tr('Rozpocznij diagnostykę', 'Begin diagnosis')
                    : _tr('Rozpocznij naprawę', 'Start approved repair'))),
          if (widget.assign != null && data.status == 'accepted' &&
              !const {'collected', 'cancelled'}.contains(data.workOrderStatus))
            OutlinedButton(key: const Key('repair_assign'), onPressed: _busy ? null : _assign,
              child: Text(_tr('Przypisz mechanika', 'Assign mechanic'))),
          if (widget.progress != null)
            for (final status in nextStatuses(data.workOrderStatus))
              OutlinedButton(key: Key('repair_progress_$status'),
                onPressed: _busy ? null : () => _updateProgress(status),
                child: Text(_status(status))),
          if (data.workOrderId != null && widget.accept != null)
            Text(_tr('Zlecenie znajdziesz w „Zlecenia i kosztorysy”.',
              'Find the work order in “Work orders and estimates”.')),
          const SizedBox(height: 12),
          ExpansionTile(
            key: const Key('repair_event_timeline'),
            title: Text(GarageUiText.get('repairTimeline')),
            subtitle: Text('${GarageUiText.get('events')}: ${data.events.length}'),
            children: [
              for (var i = 0; i < data.events.length; i++)
                Builder(builder: (context) {
                  final event = data.events[i];
                  final time = event.occurredAt.toLocal();
                  final material = MaterialLocalizations.of(context);
                  final timestamp = '${material.formatMediumDate(time)} · '
                    '${material.formatTimeOfDay(TimeOfDay.fromDateTime(time))}';
                  final details = _eventDescription(event);
                  return ListTile(
                    key: Key('repair_timeline_event_$i'),
                    dense: true,
                    leading: const Icon(Icons.history),
                    title: Text(_eventLabel(event)),
                    subtitle: Text(details == null ? timestamp
                      : '$timestamp · $details'),
                  );
                }),
            ],
          ),
        ],
      ])),
    );
  }
}
