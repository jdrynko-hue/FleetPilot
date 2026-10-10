import 'package:flutter/material.dart';

import '../company/company_screen.dart';
import '../company/manager_control_panel.dart';
import '../core/constants.dart';
import '../core/localization.dart';
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

  late List<CompanyMembership> _memberships;
  late CompanyMembership _membership;

  int _index = 0;
  int _refreshToken = 0;

  @override
  void initState() {
    super.initState();

    _memberships = List.from(widget.memberships);

    _membership = _memberships.first;
  }

  void _refreshAll() {
    setState(() => _refreshToken++);
  }

  Future<void> _reloadMemberships() async {
    final memberships = await _repository.fetchMemberships();

    if (memberships.isEmpty || !mounted) {
      return;
    }

    setState(() {
      final currentId = _membership.companyId;

      _memberships = memberships;

      _membership = memberships.firstWhere(
        (m) => m.companyId == currentId,
        orElse: () => memberships.first,
      );

      _refreshToken++;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_membership.role == 'driver') {
      return DriverHomeScreen(
        key: ValueKey(_membership.companyId),
        company: _membership,
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

        final body = IndexedStack(index: _index, children: pages);

        return Scaffold(
          appBar: AppBar(
            title: const Text('FleetPilot'),
            actions: [
              if (_memberships.length > 1)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      dropdownColor: const Color(0xFF102A43),
                      style: const TextStyle(color: Colors.white),
                      iconEnabledColor: Colors.white,
                      value: _membership.companyId,
                      items: _memberships
                          .map(
                            (m) => DropdownMenuItem(
                              value: m.companyId,
                              child: Text(m.companyName),
                            ),
                          )
                          .toList(),
                      onChanged: (id) {
                        if (id == null) {
                          return;
                        }

                        setState(() {
                          _membership = _memberships.firstWhere(
                            (m) => m.companyId == id,
                          );

                          _index = 0;
                          _refreshToken++;
                        });
                      },
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Center(child: Text(_membership.companyName)),
                ),
              if (canManage)
                IconButton(
                  tooltip: AppLocale.language.value == 'pl'
                      ? 'Panel managera'
                      : 'Manager control panel',
                  icon: const Icon(Icons.admin_panel_settings_outlined),
                  onPressed: () async {
                    await Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) =>
                            ManagerControlPanel(company: _membership),
                      ),
                    );
                    if (mounted) _refreshAll();
                  },
                ),
              IconButton(
                tooltip: tr('notifications'),
                icon: const Icon(Icons.notifications_outlined),
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => NotificationsScreen(company: _membership),
                  ),
                ),
              ),
              IconButton(
                tooltip: tr('refresh'),
                onPressed: _refreshAll,
                icon: const Icon(Icons.refresh),
              ),
              IconButton(
                tooltip: tr('sign_out'),
                onPressed: () => _repository.signOut(),
                icon: const Icon(Icons.logout),
              ),
            ],
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
