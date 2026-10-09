import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/formatters.dart';
import '../core/widgets.dart';
import '../data/fleet_repository.dart';
import '../data/models.dart';
import 'repair_form_screen.dart';

class RepairsScreen extends StatefulWidget {
  const RepairsScreen({
    required this.company,
    required this.canManage,
    required this.refreshToken,
    required this.onDataChanged,
    super.key,
  });

  final CompanyMembership company;
  final bool canManage;
  final int refreshToken;
  final VoidCallback onDataChanged;

  @override
  State<RepairsScreen> createState() => _RepairsScreenState();
}

class _RepairsScreenState extends State<RepairsScreen> {
  final _repository = FleetRepository();
  late Future<List<Repair>> _future;
  String? _status;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant RepairsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken ||
        oldWidget.company.companyId != widget.company.companyId)
      _load();
  }

  void _load() => _future = _repository.fetchRepairs(widget.company.companyId);

  Future<void> _open({Repair? repair}) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            RepairFormScreen(company: widget.company, repair: repair),
      ),
    );
    if (changed == true) {
      setState(_load);
      widget.onDataChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Repair>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done)
          return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError)
          return ErrorState(
            error: snapshot.error!,
            onRetry: () => setState(_load),
          );
        final all = snapshot.data ?? [];
        final repairs = all
            .where((r) => _status == null || r.status == _status)
            .toList();
        return Scaffold(
          backgroundColor: Colors.transparent,
          floatingActionButton: widget.canManage
              ? FloatingActionButton.extended(
                  onPressed: () => _open(),
                  icon: const Icon(Icons.add),
                  label: const Text('Add repair'),
                )
              : null,
          body: RefreshIndicator(
            onRefresh: () async => setState(_load),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Repairs',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String?>(
                    initialValue: _status,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('All statuses'),
                      ),
                      ...repairStatuses.map(
                        (s) => DropdownMenuItem<String?>(
                          value: s,
                          child: Text(prettifyEnum(s)),
                        ),
                      ),
                    ],
                    onChanged: (value) => setState(() => _status = value),
                  ),
                ),
                const SizedBox(height: 16),
                if (repairs.isEmpty)
                  const SizedBox(
                    height: 360,
                    child: EmptyState(
                      icon: Icons.build_outlined,
                      title: 'No repairs',
                      message: 'Repair jobs and costs will appear here.',
                    ),
                  )
                else
                  Card(
                    child: Column(
                      children: [
                        for (var i = 0; i < repairs.length; i++) ...[
                          ListTile(
                            onTap: widget.canManage
                                ? () => _open(repair: repairs[i])
                                : null,
                            leading: const CircleAvatar(
                              child: Icon(Icons.build_outlined),
                            ),
                            title: Text(
                              '${repairs[i].registration ?? 'Vehicle'} — ${repairs[i].description ?? 'Repair'}',
                            ),
                            subtitle: Text(
                              '${repairs[i].garageName ?? 'No garage'} • ${prettifyEnum(repairs[i].status)}',
                            ),
                            trailing: Text(
                              formatMoney(
                                repairs[i].totalCost,
                                currency: widget.company.currency,
                              ),
                            ),
                          ),
                          if (i != repairs.length - 1) const Divider(height: 1),
                        ],
                      ],
                    ),
                  ),
                const SizedBox(height: 84),
              ],
            ),
          ),
        );
      },
    );
  }
}
