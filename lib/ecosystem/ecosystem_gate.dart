import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/company_gate.dart';
import '../garage/garage_ui_text.dart';
import 'ecosystem_access.dart';
import 'ecosystem_module_hub.dart';

/// QA-only entry point. A private customer is never forced to create a fleet.
class EcosystemGate extends StatefulWidget {
  const EcosystemGate({required this.loadAccess,
    required this.destinationBuilder, required this.signOut, this.isCurrentAccount, super.key});

  factory EcosystemGate.forClient(SupabaseClient client, {Key? key}) {
    final userId = client.auth.currentUser?.id;
    return EcosystemGate(key: key,
        isCurrentAccount: () => userId != null && client.auth.currentUser?.id == userId,
        loadAccess: EcosystemAccessRepository.forClient(client).load,
        signOut: () => client.auth.signOut(),
        destinationBuilder: (destination) =>
          destination.module == EcosystemModule.fleet
            ? const CompanyGate()
            : EcosystemModuleHub(client: client, destination: destination),
      );
  }

  final Future<EcosystemAccess> Function() loadAccess;
  final Widget Function(EcosystemDestination) destinationBuilder;
  final Future<void> Function() signOut;
  final bool Function()? isCurrentAccount;
  @override
  State<EcosystemGate> createState() => _EcosystemGateState();
}

class _EcosystemGateState extends State<EcosystemGate> {
  late Future<EcosystemAccess?> _access;
  bool _signingOut = false;
  String? _error;
  @override
  void initState() { super.initState(); _access = _loadAccess(); }
  Future<EcosystemAccess?> _loadAccess() async {
    // Handle even an immediate failure before FutureBuilder subscribes.
    // The UI receives no private transport/database exception details.
    try { return await widget.loadAccess(); } catch (_) { return null; }
  }
  bool get _current => widget.isCurrentAccount?.call() ?? true;
  void _reload() {
    if (!_current) return;
    setState(() { _error = null; _access = _loadAccess(); });
  }
  void _open(EcosystemDestination destination) {
    if (_signingOut || !_current) return;
    Navigator.of(context).push<void>(MaterialPageRoute<void>(
      builder: (_) => widget.destinationBuilder(destination),
    )).then((_) { if (mounted && !_signingOut) _reload(); });
  }
  Future<void> _logout() async {
    setState(() { _signingOut = true; _error = null; });
    try { await widget.signOut(); }
    catch (_) {
      if (mounted) setState(() => _error = GarageUiText.get('signOutFailed'));
    } finally { if (mounted) setState(() => _signingOut = false); }
  }
  Widget _tile(String id, String title, IconData icon,
      EcosystemDestination destination, {String? subtitle}) => Card(
    child: ListTile(key: Key(id), leading: Icon(icon), title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: _signingOut ? null : () => _open(destination)),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Flotaryx'), actions: [
      IconButton(key: const Key('ecosystem_refresh'), onPressed: _signingOut ? null : _reload,
        tooltip: GarageUiText.get('refresh'), icon: const Icon(Icons.refresh)),
      IconButton(key: const Key('ecosystem_logout'), onPressed: _signingOut ? null : _logout,
        tooltip: GarageUiText.get('signOut'), icon: const Icon(Icons.logout)),
    ]),
    body: FutureBuilder<EcosystemAccess?>(future: _access,
      builder: (context, snapshot) {
        if (_signingOut || snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(GarageUiText.get('accessFailed')),
            FilledButton(key: const Key('ecosystem_retry'), onPressed: _reload,
              child: Text(GarageUiText.get('retry'))),
          ]));
        }
        final access = snapshot.requireData!;
        return Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(padding: const EdgeInsets.all(20), children: [
            Text(GarageUiText.get('chooseModule'),
              style: Theme.of(context).textTheme.headlineSmall),
            if (_error != null) Text(_error!),
            _tile('ecosystem_fleet', access.hasFleet ? 'Flotaryx Fleet' :
              GarageUiText.get('createFleet'), Icons.local_shipping_outlined,
              const EcosystemDestination(EcosystemModule.fleet)),
            for (final garage in access.garages)
              _tile('ecosystem_${garage.workspaceId}',
                garage.module == EcosystemModule.mechanic
                  ? GarageUiText.get('myAssignedJobs') : 'Flotaryx Garage',
                Icons.build_outlined, garage, subtitle: garage.name),
            _tile('ecosystem_customer', GarageUiText.get('workshopBookings'),
              Icons.calendar_month_outlined,
              const EcosystemDestination(EcosystemModule.customer)),
          ]),
        ));
      }),
  );
}
