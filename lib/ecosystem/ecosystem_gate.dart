import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/company_gate.dart';
import '../auth/portal_entry.dart';
import '../garage/garage_ui_text.dart';
import '../garage/create_workspace_screen.dart';
import 'ecosystem_access.dart';
import 'ecosystem_module_hub.dart';

/// QA-only entry point. A private customer is never forced to create a fleet.
class EcosystemGate extends StatefulWidget {
  const EcosystemGate({required this.loadAccess,
    required this.destinationBuilder, required this.signOut, this.isCurrentAccount, this.createWorkshopBuilder, this.preferredPortal, super.key});

  factory EcosystemGate.forClient(SupabaseClient client, {Key? key, PortalEntry? preferredPortal, bool customerSearchFirst = false, String? customerCity, String? customerWorkshopId}) {
    final userId = client.auth.currentUser?.id;
    return EcosystemGate(key: key, preferredPortal: preferredPortal,
        createWorkshopBuilder: (routeContext) => GarageCreateWorkspaceScreen.forClient(
          client: client, onCreated: () => Navigator.of(routeContext).pop()),
        isCurrentAccount: () => userId != null && client.auth.currentUser?.id == userId,
        loadAccess: EcosystemAccessRepository.forClient(client).load,
        signOut: () => client.auth.signOut(),
        destinationBuilder: (destination) =>
          destination.module == EcosystemModule.fleet
            ? const CompanyGate()
            : EcosystemModuleHub(client: client, destination: destination, customerSearchFirst: customerSearchFirst, customerCity: customerCity, customerWorkshopId: customerWorkshopId),
      );
  }

  final PortalEntry? preferredPortal;
  final Future<EcosystemAccess> Function() loadAccess;
  final Widget Function(EcosystemDestination) destinationBuilder;
  final Future<void> Function() signOut;
  final bool Function()? isCurrentAccount;
  final WidgetBuilder? createWorkshopBuilder;
  @override
  State<EcosystemGate> createState() => _EcosystemGateState();
}

class _EcosystemGateState extends State<EcosystemGate> {
  late Future<EcosystemAccess?> _access;
  bool _signingOut = false;
  bool _handledEntry = false;
  bool _opening = false;
  String? _error;
  @override
  void initState() { super.initState(); _access = _loadAccess(); }
  Future<EcosystemAccess?> _loadAccess() async {
    // Handle even an immediate failure before FutureBuilder subscribes.
    // The UI receives no private transport/database exception details.
    try { return await widget.loadAccess(); } catch (_) { return null; }
  }
  bool get _current => widget.isCurrentAccount?.call() ?? true;
  bool get _garagePortal => widget.preferredPortal == PortalEntry.garage;
  void _reload() {
    if (!_current) return;
    setState(() { _error = null; _access = _loadAccess(); });
  }
  void _open(EcosystemDestination destination) {
    if (_opening || _signingOut || !_current) return;
    if (_garagePortal && destination.module != EcosystemModule.workshop &&
        destination.module != EcosystemModule.mechanic) return;
    _opening = true;
    Navigator.of(context).push<void>(MaterialPageRoute<void>(
      builder: (_) => widget.destinationBuilder(destination),
    )).then((_) {
      _opening = false;
      if (mounted && !_signingOut && _current) _reload();
    });
  }
  void _createWorkshop() {
    if (!mounted || _opening || _signingOut || !_current || widget.createWorkshopBuilder == null) return;
    _opening = true;
    Navigator.of(context).push<void>(MaterialPageRoute<void>(
      builder: widget.createWorkshopBuilder!,
    )).then((_) {
      _opening = false;
      if (mounted && !_signingOut && _current) _reload();
    });
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
    appBar: AppBar(title: Text(_garagePortal ? 'Flotaryx Garage' : 'Flotaryx'), actions: [
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
        if (!_handledEntry && _current) {
          _handledEntry = true;
          if (widget.preferredPortal == PortalEntry.garage &&
              access.garages.isEmpty && widget.createWorkshopBuilder != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _createWorkshop());
          }
          EcosystemDestination? destination;
          if (widget.preferredPortal == PortalEntry.fleet) {
            destination = const EcosystemDestination(EcosystemModule.fleet);
          } else if (widget.preferredPortal == PortalEntry.customer) {
            destination = const EcosystemDestination(EcosystemModule.customer);
          } else if (widget.preferredPortal == PortalEntry.garage && access.garages.length == 1) {
            destination = access.garages.single;
          }
          if (destination != null) {
            final target = destination;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _current && !_signingOut) _open(target);
            });
          }
        }
        return Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(padding: const EdgeInsets.all(20), children: [
            if (!_garagePortal)
              Text(GarageUiText.get('chooseModule'),
                style: Theme.of(context).textTheme.headlineSmall),
            if (_error != null) Text(_error!),
            if (!_garagePortal)
              _tile('ecosystem_fleet', access.hasFleet ? 'Flotaryx Fleet' :
                GarageUiText.get('createFleet'), Icons.local_shipping_outlined,
                const EcosystemDestination(EcosystemModule.fleet)),
            if (widget.createWorkshopBuilder != null)
              Card(child: ListTile(key: const Key('ecosystem_create_workshop'),
                leading: const Icon(Icons.add_business_outlined),
                title: Text(GarageUiText.get('createWorkshop')),
                trailing: const Icon(Icons.chevron_right),
                onTap: _signingOut ? null : _createWorkshop)),
            for (final garage in access.garages)
              _tile('ecosystem_${garage.workspaceId}',
                garage.module == EcosystemModule.mechanic
                  ? GarageUiText.get('myAssignedJobs') : 'Flotaryx Garage',
                Icons.build_outlined, garage, subtitle: garage.name),
            if (!_garagePortal)
              _tile('ecosystem_customer', GarageUiText.get('workshopBookings'),
                Icons.calendar_month_outlined,
                const EcosystemDestination(EcosystemModule.customer)),
          ]),
        ));
      }),
  );
}
