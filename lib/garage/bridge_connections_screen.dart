import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/localization.dart';
import '../data/fleet_repository.dart';
import '../data/models.dart';
import 'consumer_booking_repository.dart';
import 'repair_bridge_repository.dart';

/// QA consent management. Discovery includes only opted-in public profiles.
class GarageBridgeConnectionsScreen extends StatefulWidget {
  const GarageBridgeConnectionsScreen({required this.fleet, required this.load,
    required this.connect, this.search, this.loadIssues, this.send, super.key});
  factory GarageBridgeConnectionsScreen.forClient({required SupabaseClient client,
    required String scopeId, required bool fleet}) {
    final repo = GarageRepairBridgeRepository(client);
    final user = client.auth.currentUser?.id;
    void check() {
      if (user == null || client.auth.currentUser?.id != user) throw StateError('Account changed');
    }
    return GarageBridgeConnectionsScreen(
      fleet: fleet,
      load: () async { check(); final rows = await repo.connections(scopeId, fleet: fleet); check(); return rows; },
      search: !fleet ? null : (city) async {
        check(); final rows = await GarageBookingRepository(client).findWorkshops(city: city); check(); return rows;
      },
      connect: (shop, company) async {
        check();
        final id = fleet ? await repo.requestConnection(scopeId, shop)
          : await repo.acceptConnection(company, scopeId);
        check(); return id;
      },
      loadIssues: !fleet ? null : () async {
        check(); final rows = await FleetRepository(client).fetchIssues(scopeId); check();
        return rows.where((r) => r.companyId == scopeId && !const {'closed', 'resolved'}.contains(r.status)).toList();
      },
      send: !fleet ? null : (shop, issue, description, registration) async {
        check(); final id = await repo.sendIssue(companyId: scopeId, workspaceId: shop,
          issueId: issue.id, shareDescription: description, shareRegistration: registration);
        check(); return id;
      },
    );
  }
  final bool fleet;
  final Future<List<GarageFleetConnection>> Function() load;
  final Future<List<GarageBookingWorkshop>> Function(String)? search;
  final Future<String> Function(String shop, String company) connect;
  final Future<List<FleetIssue>> Function()? loadIssues;
  final Future<String> Function(String shop, FleetIssue issue, bool description, bool registration)? send;
  @override
  State<GarageBridgeConnectionsScreen> createState() => _ConnectionsState();
}

class _ConnectionsState extends State<GarageBridgeConnectionsScreen> {
  final _city = TextEditingController();
  List<GarageFleetConnection> _rows = const [];
  List<GarageBookingWorkshop> _shops = const [];
  bool _busy = true;
  String? _notice;
  int _generation = 0;
  String _tr(String pl, String en) => AppLocale.language.value == 'pl' ? pl : en;
  @override
  void initState() { super.initState(); _reload(); }
  @override
  void dispose() { _city.dispose(); super.dispose(); }
  @override
  void didUpdateWidget(covariant GarageBridgeConnectionsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.load != widget.load) { _shops = const []; _reload(); }
  }
  Future<void> _reload() async {
    final generation = ++_generation;
    setState(() { _busy = true; _rows = const []; _notice = null; });
    try {
      final rows = await widget.load();
      if (mounted && generation == _generation) setState(() => _rows = rows);
    } catch (_) {
      if (mounted && generation == _generation) setState(() {
        _shops = const [];
        _notice = _tr('Nie udało się sprawdzić połączeń. Odśwież.', 'Could not verify connections. Refresh.');
      });
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }
  Future<void> _search() async {
    if (_busy || widget.search == null) return;
    final generation = ++_generation;
    setState(() { _busy = true; _shops = const []; _notice = null; });
    try {
      final shops = await widget.search!(_city.text.trim());
      if (mounted && generation == _generation) setState(() {
        _shops = shops;
        if (shops.isEmpty) _notice = _tr('Brak opublikowanych warsztatów dla tego miejsca.', 'No published workshops for this location.');
      });
    } catch (_) {
      if (mounted && generation == _generation) setState(() => _notice = _tr('Wyszukiwanie nie powiodło się.', 'Search failed.'));
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }
  Future<void> _connect(String shop, String company, String name) async {
    if (_busy) return;
    setState(() => _busy = true);
    final generation = _generation;
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: Text(name),
      content: Text(widget.fleet
        ? _tr('Wyślij prośbę o połączenie. Warsztat musi ją zaakceptować. Nie wysyła to usterek.',
          'Request a connection. The workshop must accept it. This does not send defects.')
        : _tr('Zezwól tej flocie na wysyłanie usterek do warsztatu. Nazwa firmy nie oznacza zweryfikowanej tożsamości.',
          'Allow this fleet to send defects to the workshop. A company name is not verified identity.')),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: Text(_tr('Anuluj', 'Cancel'))),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(_tr('Potwierdź', 'Confirm')))],
    ));
    if (!mounted || generation != _generation) return;
    if (confirmed != true) { setState(() => _busy = false); return; }
    try {
      await widget.connect(shop, company);
      if (mounted && generation == _generation) await _reload();
    } catch (_) {
      if (mounted && generation == _generation) setState(() {
        _rows = const []; _shops = const []; _busy = false;
        _notice = _tr('Nie potwierdzono operacji. Odśwież przed kolejną próbą.',
          'Operation was not confirmed. Refresh before trying again.');
      });
    }
  }
  Future<void> _send(GarageFleetConnection connection) async {
    if (_busy || widget.loadIssues == null || widget.send == null) return;
    setState(() => _busy = true);
    final generation = _generation;
    try {
      final issues = await widget.loadIssues!();
      if (!mounted || generation != _generation) return;
      FleetIssue? selected;
      var description = false;
      var registration = false;
      final choice = await showDialog<(FleetIssue, bool, bool)>(context: context, builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(connection.workspaceName),
          content: SizedBox(width: 360, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_tr('Domyślnie wysyłany jest tylko tytuł usterki. To zgłoszenie, nie potwierdzony termin ani zgoda na koszty.',
              'Only the defect title is shared by default. This is a request, not a confirmed appointment or cost approval.')),
            DropdownButtonFormField<FleetIssue>(isExpanded: true, initialValue: selected,
              decoration: InputDecoration(labelText: _tr('Otwarta usterka', 'Open defect')),
              items: [for (final issue in issues) DropdownMenuItem(value: issue,
                child: Text(issue.title, overflow: TextOverflow.ellipsis))],
              onChanged: (value) => update(() => selected = value)),
            CheckboxListTile(value: description, title: Text(_tr('Udostępnij opis', 'Share description')),
              onChanged: (value) => update(() => description = value ?? false)),
            CheckboxListTile(value: registration, title: Text(_tr('Udostępnij rejestrację', 'Share registration')),
              onChanged: (value) => update(() => registration = value ?? false)),
            if (issues.isEmpty) Text(_tr('Brak otwartych usterek.', 'No open defects.')),
          ]))),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(_tr('Anuluj', 'Cancel'))),
            FilledButton(key: const Key('bridge_send_confirm'), onPressed: selected == null ? null
              : () => Navigator.pop(context, (selected!, description, registration)),
              child: Text(_tr('Wyślij zgłoszenie', 'Send request')))],
        ),
      ));
      if (!mounted || generation != _generation) return;
      if (choice == null) { setState(() => _busy = false); return; }
      final current = await widget.load();
      if (!mounted || generation != _generation) return;
      if (!current.any((r) => r.companyId == connection.companyId &&
          r.workspaceId == connection.workspaceId && r.status == 'active')) throw StateError('Consent unavailable');
      await widget.send!(connection.workspaceId, choice.$1, choice.$2, choice.$3);
      if (!mounted || generation != _generation) return;
      await _reload();
      if (mounted) setState(() => _notice = _tr('Wysłano zgłoszenie. Sprawdź je w naprawach Fleet ↔ Garage.',
        'Request sent. View it in Fleet ↔ Garage repairs.'));
    } catch (_) {
      if (mounted && generation == _generation) setState(() {
        _busy = false; _rows = const []; _shops = const [];
        _notice = _tr('Nie potwierdzono wysłania. Sprawdź listę napraw przed kolejną próbą.',
          'Sending was not confirmed. Check the repair inbox before trying again.');
      });
    }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_tr('Połączenia Fleet ↔ Garage', 'Fleet ↔ Garage connections')),
      actions: [IconButton(onPressed: _busy ? null : _reload, icon: const Icon(Icons.refresh), tooltip: _tr('Odśwież', 'Refresh'))]),
    body: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: [
      if (_busy && _rows.isEmpty && _shops.isEmpty) const LinearProgressIndicator(),
      if (_notice != null) Text(_notice!),
      if (widget.search != null) ...[
        TextField(controller: _city, enabled: !_busy, decoration: InputDecoration(labelText: _tr('Miasto', 'City'))),
        OutlinedButton(onPressed: _busy ? null : _search, child: Text(_tr('Znajdź opublikowany warsztat', 'Find a published workshop'))),
        for (final shop in _shops)
          ListTile(title: Text(shop.name), subtitle: Text('${shop.city}, ${shop.country}'),
            trailing: const Icon(Icons.add_link), onTap: _busy || _rows.any((r) => r.workspaceId == shop.workspaceId)
              ? null : () => _connect(shop.workspaceId, '', shop.name)),
      ],
      for (final row in _rows) Card(child: ListTile(
        title: Text(widget.fleet ? row.workspaceName : row.companyName),
        subtitle: Text(switch (row.status) {
          'active' => _tr('Połączenie aktywne', 'Connection active'),
          'revoked' => _tr('Zgoda wycofana', 'Consent revoked'),
          _ => _tr('Oczekuje na zgodę warsztatu', 'Awaiting workshop consent'),
        }),
        onTap: _busy ? null : !widget.fleet && row.status == 'pending'
          ? () => _connect(row.workspaceId, row.companyId, row.companyName)
          : widget.fleet && row.status == 'active' ? () => _send(row) : null,
        trailing: !widget.fleet && row.status == 'pending' ? const Icon(Icons.how_to_reg)
          : widget.fleet && row.status == 'active' ? const Icon(Icons.send) : null,
      )),
      if (!_busy && _rows.isEmpty) Text(_tr('Brak połączeń.', 'No connections.')),
    ])),
  );
}
