import 'package:flutter/material.dart';
import '../auth/create_company_screen.dart';

import '../company/company_screen.dart';
import '../company/manager_control_panel.dart';
import '../core/constants.dart';
import '../core/localization.dart';
import 'fleet_app_bar.dart';
import 'fleet_membership_controller.dart';
import '../dashboard/dashboard_screen.dart';
import '../data/fleet_repository.dart';
import '../data/models.dart';
import '../drivers/drivers_screen.dart';
import '../drivers/driver_home_screen.dart';
import '../garages/garages_screen.dart';
import '../issues/issues_screen.dart';
import '../notifications/notifications_screen.dart';
import '../repairs/repairs_screen.dart';
import '../reports/reports_screen.dart';
import '../vehicles/vehicles_screen.dart';

class FleetShell extends StatefulWidget {
  const FleetShell({required this.memberships, super.key});

  final List<CompanyMembership> memberships;

  @override
  State<FleetShell> createState() => _FleetShellState();
}

class _FleetShellState extends State<FleetShell> {
  final _repository = FleetRepository();

  late final FleetMembershipController _access;
  List<CompanyMembership> get _memberships => _access.memberships;
  CompanyMembership get _membership => _access.selected!;

  int _index = 0;
  int _refreshToken = 0;
  bool _creatingFleet = false;

  @override
  void initState() {
    super.initState();

    final memberships = widget.memberships;

    // A checkout may return from any fleet, not necessarily the first one.
    // Resolve the URL hint against memberships fetched under this user's RLS.
    final billingReturn = Uri.base.queryParameters['billing'];
    final returnedFleetId = Uri.base.queryParameters['fleet'];
    final selected = memberships.firstWhere(
      (member) =>
          (billingReturn == 'success' || billingReturn == 'cancel') &&
          member.companyId == returnedFleetId,
      orElse: () => memberships.first,
    );

    _access = FleetMembershipController(
      memberships: memberships,
      selectedId: selected.companyId,
      load: _repository.fetchMemberships,
      currentAccountId: () => _repository.currentUser?.id,
    )..addListener(_accessChanged);

    // Stripe returns to /app/?billing=success or ?billing=cancel.
    // These URL parameters describe the Checkout navigation result,
    // not a verified payment; subscription status comes from webhooks.
    if (billingReturn == 'success' || billingReturn == 'cancel') {
      _index = 7; // Company → Subscription and billing
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final polish = AppLocale.language.value == 'pl';
        final message = billingReturn == 'success'
            ? (polish
                ? 'Powrót ze Stripe. Potwierdzenie płatności może chwilę potrwać. Sprawdź status w Abonamentach.'
                : 'Returned from Stripe. Payment confirmation may take a moment. Check the status in Subscriptions.')
            : (polish
                ? 'Płatność w Stripe została przerwana. Możesz ponownie wybrać abonament.'
                : 'Stripe Checkout was canceled. You can choose a subscription again.');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), duration: const Duration(seconds: 8)),
        );
      });
    }
  }

  void _refreshAll() {
    setState(() => _refreshToken++);
  }

  void _accessChanged() {
    if (mounted) setState(() { _index = 0; _refreshToken++; });
  }

  Future<void> _reloadMemberships() => _access.refresh();

  Future<void> _openAdditionalFleet() async {
    if (_creatingFleet || _access.loading ||
        !{'owner', 'admin'}.contains(_membership.role)) return;
    final account = _repository.currentUser?.id;
    if (account == null) return;
    final previousIds = _memberships.map((member) => member.companyId).toSet();
    var refresh = false;
    _creatingFleet = true;
    try {
      await Navigator.of(context).push<void>(MaterialPageRoute<void>(
        builder: (routeContext) => CreateCompanyScreen(allowCancel: true,
          onCreated: () {
            refresh = true;
            Navigator.of(routeContext).pop();
          }),
      ));
      if (!mounted || _repository.currentUser?.id != account || !refresh) return;
      await _reloadMemberships();
      if (!mounted || _repository.currentUser?.id != account || _access.failed) return;
      final added = _memberships.where((member) => !previousIds.contains(member.companyId)).toList();
      if (added.length == 1) _access.select(added.single.companyId);
    } finally {
      _creatingFleet = false;
    }
  }

  @override
  void dispose() {
    _access.removeListener(_accessChanged);
    _access.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_access.loading || _access.selected == null) {
      final polish = AppLocale.language.value == 'pl';
      return Scaffold(
        appBar: AppBar(title: const Text('Flotaryx')),
        body: Center(child: _access.loading
          ? const CircularProgressIndicator()
          : Column(mainAxisSize: MainAxisSize.min, children: [
              Text(_access.failed
                ? (polish ? 'Nie można sprawdzić dostępu do flot.' : 'Unable to check fleet access.')
                : (polish ? 'Brak dostępu do flot.' : 'No fleet access.')),
              FilledButton(onPressed: _reloadMemberships, child: Text(tr('refresh'))),
              TextButton(onPressed: () => _repository.signOut(), child: Text(tr('sign_out'))),
            ])),
      );
    }
    if (_membership.role == 'driver') {
      return DriverHomeScreen(
        key: ValueKey('${_membership.companyId}:${_membership.role}'),
        company: _membership,
        memberships: _memberships,
        onAccessRefresh: _reloadMemberships,
        onFleetSelected: (id) {
          if (id == _membership.companyId) return;
          _access.select(id);
        },
      );
    }

    final canManage = canManageForRole(_membership.role);

    final pages = [
      DashboardScreen(company: _membership, refreshToken: _refreshToken),
      VehiclesScreen(
        company: _membership,
        canManage: canManage,
        refreshToken: _refreshToken,
        onDataChanged: _refreshAll,
      ),
      DriversScreen(
        company: _membership,
        canManage: canManage,
        refreshToken: _refreshToken,
        onDataChanged: _refreshAll,
      ),
      IssuesScreen(
        company: _membership,
        canManage: canManage,
        refreshToken: _refreshToken,
        onDataChanged: _refreshAll,
      ),
      RepairsScreen(
        company: _membership,
        canManage: canManage,
        refreshToken: _refreshToken,
        onDataChanged: _refreshAll,
      ),
      GaragesScreen(
        company: _membership,
        canManage: canManage,
        refreshToken: _refreshToken,
        onDataChanged: _refreshAll,
      ),
      ReportsScreen(company: _membership, refreshToken: _refreshToken),
      CompanyScreen(
        company: _membership,
        onMembershipChanged: _reloadMemberships,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;

        // Reset screen state when switching fleets. Besides refreshing queries,
        // this prevents cached widgets from briefly showing the previous fleet.
        final body = IndexedStack(
          key: ValueKey('${_membership.companyId}:${_membership.role}'),
          index: _index,
          // IndexedStack keeps inactive pages mounted. Only the visible tab
          // participates in route Hero animations (each page has an add FAB).
          children: [
            for (var i = 0; i < pages.length; i++)
              HeroMode(enabled: i == _index, child: pages[i]),
          ],
        );

        return Scaffold(
          appBar: FleetAppBar(
            memberships: _memberships,
            selectedMembership: _membership,
            canManage: canManage,
            compact: !wide,
            onFleetSelected: (id) {
              if (id == _membership.companyId) return;
              _access.select(id);
            },
            onManagerPressed: () async {
              await Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => ManagerControlPanel(company: _membership),
                ),
              );
              if (mounted) _refreshAll();
            },
            onNotificationsPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => NotificationsScreen(company: _membership),
              ),
            ),
            onCreateFleetPressed: {'owner', 'admin'}.contains(_membership.role)
                ? _openAdditionalFleet : null,
            onRefreshPressed: _reloadMemberships,
            onSignOutPressed: () => _repository.signOut(),
          ),
          body: wide
              ? Row(
                  children: [
                    NavigationRail(
                      selectedIndex: _index,
                      onDestinationSelected: (value) =>
                          setState(() => _index = value),
                      labelType: NavigationRailLabelType.all,
                      destinations: [
                        NavigationRailDestination(
                          icon: const Icon(Icons.dashboard_outlined),
                          label: Text(tr('dashboard')),
                        ),
                        NavigationRailDestination(
                          icon: const Icon(Icons.local_shipping_outlined),
                          label: Text(tr('vehicles')),
                        ),
                        NavigationRailDestination(
                          icon: const Icon(Icons.people_outline),
                          label: Text(tr('drivers')),
                        ),
                        NavigationRailDestination(
                          icon: const Icon(Icons.report_problem_outlined),
                          label: Text(tr('issues')),
                        ),
                        NavigationRailDestination(
                          icon: const Icon(Icons.build_outlined),
                          label: Text(tr('repairs')),
                        ),
                        NavigationRailDestination(
                          icon: const Icon(Icons.garage_outlined),
                          label: Text(tr('garages')),
                        ),
                        NavigationRailDestination(
                          icon: const Icon(Icons.bar_chart_outlined),
                          label: Text(tr('reports')),
                        ),
                        NavigationRailDestination(
                          icon: const Icon(Icons.business_outlined),
                          label: Text(tr('company')),
                        ),
                      ],
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: body),
                  ],
                )
              : body,
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  selectedIndex: _index > 4 ? 4 : _index,
                  onDestinationSelected: (value) {
                    if (value < 4) {
                      setState(() => _index = value);
                    } else {
                      _showMoreSheet(context);
                    }
                  },
                  destinations: [
                    NavigationDestination(
                      icon: const Icon(Icons.dashboard_outlined),
                      label: tr('dashboard'),
                    ),
                    NavigationDestination(
                      icon: const Icon(Icons.local_shipping_outlined),
                      label: tr('vehicles'),
                    ),
                    NavigationDestination(
                      icon: const Icon(Icons.people_outline),
                      label: tr('drivers'),
                    ),
                    NavigationDestination(
                      icon: const Icon(Icons.report_problem_outlined),
                      label: tr('issues'),
                    ),
                    NavigationDestination(
                      icon: const Icon(Icons.more_horiz),
                      label: tr('more'),
                    ),
                  ],
                ),
        );
      },
    );
  }

  void _showMoreSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canManageForRole(_membership.role))
              ListTile(
                leading: const Icon(Icons.admin_panel_settings_outlined),
                title: Text(
                  AppLocale.language.value == 'pl'
                      ? 'Panel managera'
                      : 'Manager control panel',
                ),
                onTap: () async {
                  Navigator.pop(context);
                  await Navigator.of(this.context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => ManagerControlPanel(company: _membership),
                    ),
                  );
                  if (mounted) _refreshAll();
                },
              ),
            ListTile(
              leading: const Icon(Icons.build_outlined),
              title: Text(tr('repairs')),
              onTap: () {
                Navigator.pop(context);
                setState(() => _index = 4);
              },
            ),
            ListTile(
              leading: const Icon(Icons.garage_outlined),
              title: Text(tr('garages')),
              onTap: () {
                Navigator.pop(context);
                setState(() => _index = 5);
              },
            ),
            ListTile(
              leading: const Icon(Icons.bar_chart_outlined),
              title: Text(tr('reports')),
              onTap: () {
                Navigator.pop(context);
                setState(() => _index = 6);
              },
            ),
            ListTile(
              leading: const Icon(Icons.business_outlined),
              title: Text(tr('company')),
              subtitle: Text('${tr('team')} • ${tr('settings')}'),
              onTap: () {
                Navigator.pop(context);
                setState(() => _index = 7);
              },
            ),
          ],
        ),
      ),
    );
  }
}
