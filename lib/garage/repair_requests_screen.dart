import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/localization.dart';
import 'repair_bridge_repository.dart';

/// QA module only. The RPC checks current membership and active connections.
class GarageRepairRequestsScreen extends StatefulWidget {
  const GarageRepairRequestsScreen({required this.load, this.loadDetail, this.accept, super.key});

  factory GarageRepairRequestsScreen.forClient({
    required SupabaseClient client, required String workspaceId,
  }) {
    final user = client.auth.currentUser?.id;
    final repository = GarageRepairBridgeRepository(client);
    void checkAccount() {
      if (user == null || client.auth.currentUser?.id != user) {
        throw StateError('Account changed');
      }
    }
    return GarageRepairRequestsScreen(
      load: () async {
        checkAccount();
        final rows = await repository.requests(workspaceId);
        checkAccount();
        return rows;
      },
      loadDetail: (row) async {
        checkAccount();
        final data = await repository.load(row.id);
        checkAccount();
        return data;
      },
      accept: (row) async {
        checkAccount();
        final id = await repository.acceptRepairRequest(row.id);
        checkAccount();
        return id;
      },
    );
  }

  final Future<List<GarageRepairRequest>> Function() load;
  final Future<GarageRepairBridgeSnapshot> Function(GarageRepairRequest)? loadDetail;
  final Future<String> Function(GarageRepairRequest)? accept;

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
      title: Text(_tr('Zgłoszenia flot', 'Fleet repair requests')),
      actions: [IconButton(
        tooltip: _tr('Odśwież', 'Refresh'),
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
            Text(_tr('Brak zgłoszeń flot dla tego warsztatu.',
                'No fleet repair requests for this workshop.')),
          for (final row in _rows)
            Card(child: ListTile(
              onTap: widget.loadDetail == null ? null : () async {
                await Navigator.of(context).push<void>(MaterialPageRoute(
                  builder: (_) => GarageRepairRequestDetailScreen(
                    request: row, load: () => widget.loadDetail!(row),
                    accept: widget.accept == null ? null : () => widget.accept!(row),
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
    required this.load, this.accept, super.key});
  final GarageRepairRequest request;
  final Future<GarageRepairBridgeSnapshot> Function() load;
  final Future<String> Function()? accept;
  @override
  State<GarageRepairRequestDetailScreen> createState() => _RepairDetailState();
}

class _RepairDetailState extends State<GarageRepairRequestDetailScreen> {
  GarageRepairBridgeSnapshot? _snapshot;
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
    setState(() { _busy = true; _snapshot = null; _error = null; });
    try {
      final data = await _loadScoped();
      if (mounted && generation == _generation) setState(() => _snapshot = data);
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

  @override
  Widget build(BuildContext context) {
    final data = _snapshot;
    return Scaffold(
      appBar: AppBar(title: Text(_tr('Zgłoszenie floty', 'Fleet repair request')),
        actions: [IconButton(tooltip: _tr('Odśwież', 'Refresh'),
          onPressed: _busy ? null : _refresh, icon: const Icon(Icons.refresh))]),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: [
        if (_busy && data == null) const Center(child: CircularProgressIndicator()),
        if (_error != null) ...[
          Text(_error!),
          TextButton(onPressed: _busy ? null : _refresh,
            child: Text(_tr('Odśwież', 'Refresh'))),
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
          if (data.workOrderId != null)
            Text(_tr('Zlecenie znajdziesz w „Zlecenia i kosztorysy”.',
              'Find the work order in “Work orders and estimates”.')),
        ],
      ])),
    );
  }
}
