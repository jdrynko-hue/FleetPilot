import 'package:flutter/material.dart';

import '../core/localization.dart';

import '../core/widgets.dart';
import '../data/fleet_repository.dart';
import '../data/models.dart';
import 'garage_form_screen.dart';

class GaragesScreen extends StatefulWidget {
  const GaragesScreen({
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
  State<GaragesScreen> createState() => _GaragesScreenState();
}

class _GaragesScreenState extends State<GaragesScreen> {
  final _repository = FleetRepository();
  late Future<List<Garage>> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant GaragesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken ||
        oldWidget.company.companyId != widget.company.companyId)
      _load();
  }

  void _load() => _future = _repository.fetchGarages(widget.company.companyId);

  Future<void> _open({Garage? garage}) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            GarageFormScreen(company: widget.company, garage: garage),
      ),
    );
    if (changed == true) {
      setState(_load);
      widget.onDataChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Garage>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done)
          return Center(child: CircularProgressIndicator());
        if (snapshot.hasError)
          return ErrorState(
            error: snapshot.error!,
            onRetry: () => setState(_load),
          );
        final garages = snapshot.data ?? [];
        return Scaffold(
          backgroundColor: Colors.transparent,
          floatingActionButton: widget.canManage
              ? FloatingActionButton.extended(
                  onPressed: () => _open(),
                  icon: const Icon(Icons.add),
                  label: Text(tr('add_garage')),
                )
              : null,
          body: RefreshIndicator(
            onRefresh: () async => setState(_load),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  tr('garages'),
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                SizedBox(height: 16),
                if (garages.isEmpty)
                  SizedBox(
                    height: 360,
                    child: EmptyState(
                      icon: Icons.garage_outlined,
                      title: tr('no_garages_yet'),
                      message: tr('no_garages_message'),
                    ),
                  )
                else
                  Card(
                    child: Column(
                      children: [
                        for (var i = 0; i < garages.length; i++) ...[
                          ListTile(
                            onTap: widget.canManage
                                ? () => _open(garage: garages[i])
                                : null,
                            leading: const CircleAvatar(
                              child: Icon(Icons.garage_outlined),
                            ),
                            title: Text(garages[i].name),
                            subtitle: Text(
                              [
                                if ((garages[i].contactName ?? '').isNotEmpty)
                                  garages[i].contactName!,
                                if ((garages[i].phone ?? '').isNotEmpty)
                                  garages[i].phone!,
                                if ((garages[i].city ?? '').isNotEmpty)
                                  garages[i].city!,
                              ].join(' • '),
                            ),
                          ),
                          if (i != garages.length - 1) const Divider(height: 1),
                        ],
                      ],
                    ),
                  ),
                SizedBox(height: 84),
              ],
            ),
          ),
        );
      },
    );
  }
}
