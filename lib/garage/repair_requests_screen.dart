import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/localization.dart';
import 'repair_bridge_repository.dart';

/// QA module only. The RPC checks current membership and active connections.
class GarageRepairRequestsScreen extends StatefulWidget {
  const GarageRepairRequestsScreen({required this.load, super.key});

  factory GarageRepairRequestsScreen.forClient({
    required SupabaseClient client, required String workspaceId,
  }) => GarageRepairRequestsScreen(
    load: () => GarageRepairBridgeRepository(client).requests(workspaceId),
  );

  final Future<List<GarageRepairRequest>> Function() load;

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
              title: Text(row.title),
              subtitle: Text(row.status == 'sent'
                ? _tr('Oczekuje na przyjęcie', 'Awaiting workshop acceptance')
                : _tr('Przyjęte przez warsztat', 'Accepted by workshop')),
            )),
        ])),
  );
}
