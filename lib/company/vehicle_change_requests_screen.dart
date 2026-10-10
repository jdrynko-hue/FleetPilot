import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/localization.dart';
import '../data/models.dart';

class VehicleChangeRequestsScreen extends StatefulWidget {
  const VehicleChangeRequestsScreen({required this.company, super.key});
  final CompanyMembership company;

  @override
  State<VehicleChangeRequestsScreen> createState() =>
      _VehicleChangeRequestsScreenState();
}

class _VehicleChangeRequestsScreenState
    extends State<VehicleChangeRequestsScreen> {
  final _client = Supabase.instance.client;
  late Future<List<Map<String, dynamic>>> _future;
  String _phrase(String en, String pl) =>
      AppLocale.language.value == 'pl' ? pl : en;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _future = _fetch();

  Future<List<Map<String, dynamic>>> _fetch() async {
    final result = await _client.rpc(
      'fleetpilot_list_vehicle_change_requests',
      params: {'_company_id': widget.company.companyId},
    );
    return (result as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<void> _decide(Map<String, dynamic> item, bool approved) async {
    final note = TextEditingController();
    final confirmed = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          approved
              ? _phrase('Approve van change?', 'Zatwierdzić zmianę vana?')
              : _phrase('Reject van change?', 'Odrzucić zmianę vana?'),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${item['driver_name']}: ${item['from_registration'] ?? '—'} → ${item['to_registration']}',
            ),
            const SizedBox(height: 10),
            Text('${item['reason']}'),
            const SizedBox(height: 10),
            TextField(
              controller: note,
              maxLength: 1000,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: _phrase(
                  'Manager note (optional)',
                  'Notatka managera (opcjonalnie)',
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_phrase('Cancel', 'Anuluj')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, {'note': note.text.trim()}),
            child: Text(
              approved
                  ? _phrase('Approve', 'Zatwierdź')
                  : _phrase('Reject', 'Odrzuć'),
            ),
          ),
        ],
      ),
    );
    note.dispose();
    if (confirmed == null || !mounted) return;
    try {
      await _client.rpc(
        'fleetpilot_review_vehicle_change',
        params: {
          '_request_id': item['id'].toString(),
          '_approve': approved,
          '_review_note': confirmed['note'],
        },
      );
      if (mounted) {
        setState(_reload);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              approved
                  ? _phrase('Van change approved.', 'Zmiana vana zatwierdzona.')
                  : _phrase('Request rejected.', 'Prośba odrzucona.'),
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${_phrase('Unable to review request', 'Nie można rozpatrzyć prośby')}: $error',
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_phrase('Van change requests', 'Prośby o zmianę vana')),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () => setState(_reload),
        ),
      ],
    ),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          if (snapshot.hasError)
            return Center(child: Text('${snapshot.error}'));
          return const Center(child: CircularProgressIndicator());
        }
        final requests = snapshot.data!;
        if (requests.isEmpty)
          return Center(child: Text(_phrase('No requests.', 'Brak próśb.')));
        return RefreshIndicator(
          onRefresh: () async {
            setState(_reload);
            await _future;
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final item in requests)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item['driver_name'].toString(),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          '${item['from_registration'] ?? '—'} → ${item['to_registration']}',
                        ),
                        Text('${item['reason']}'),
                        const SizedBox(height: 5),
                        Text(
                          '${_phrase('Status', 'Status')}: ${item['status']}',
                        ),
                        if (item['review_note'] != null)
                          Text('${item['review_note']}'),
                        if (item['status'] == 'pending')
                          Row(
                            children: [
                              OutlinedButton(
                                onPressed: () => _decide(item, false),
                                child: Text(_phrase('Reject', 'Odrzuć')),
                              ),
                              const SizedBox(width: 10),
                              FilledButton(
                                onPressed: () => _decide(item, true),
                                child: Text(_phrase('Approve', 'Zatwierdź')),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );
}
