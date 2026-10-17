import 'package:flutter/material.dart';
import '../core/localization.dart';
import 'garage_shell_text.dart';
import 'garage_ui_text.dart';

/// Fleet's responsive navigation pattern, with lazy workshop pages.
/// Inactive tabs retain their state without making unvisited API requests.
class GarageShell extends StatefulWidget {
  const GarageShell({required this.scopeId, required this.workshopName,
    required this.pages, super.key}) : assert(pages.length == 5);
  final String scopeId;
  final String workshopName;
  final List<WidgetBuilder> pages;
  static const icons = [Icons.dashboard_outlined, Icons.calendar_month_outlined,
    Icons.build_outlined, Icons.inbox_outlined, Icons.more_horiz];
  static void selectTab(BuildContext context, int index) {
    if (index >= 0 && index < 5) {
      context.findAncestorStateOfType<_GarageShellState>()?._select(index);
    }
  }
  @override
  State<GarageShell> createState() => _GarageShellState();
}

class _GarageShellState extends State<GarageShell> {
  int _index = 0;
  final Map<int, Widget> _visited = {};
  @override
  void didUpdateWidget(covariant GarageShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scopeId != widget.scopeId) {
      FocusManager.instance.primaryFocus?.unfocus();
      _index = 0;
      _visited.clear();
    }
  }
  void _select(int index) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
    final wide = box.maxWidth >= 900; // Same breakpoint as FleetShell.
    final labels = [tr('dashboard'), for (var i=0;i<3;i++) GarageShellText.tab(i), tr('more')];
    _visited.putIfAbsent(_index, () => Builder(
      key: ValueKey('${widget.scopeId}:$_index'), builder: widget.pages[_index]));
    final body = IndexedStack(index: _index, children: [
      for (var i=0;i<5;i++) HeroMode(enabled: i==_index,
        child: _visited[i] ?? const SizedBox.shrink()),
    ]);
    return Scaffold(
      appBar: AppBar(titleSpacing: wide ? null : 8,
        title: Row(children: [
          Image.asset('assets/branding/flotaryx_mark.png', width: wide ? 32 : 26,
            height: wide ? 32 : 26),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Flotaryx Garage', maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(widget.workshopName, key: const Key('garage_workspace_name'),
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70)),
          ])),
        ])),
      body: wide ? Row(children: [
        NavigationRail(selectedIndex: _index, onDestinationSelected: _select,
          labelType: NavigationRailLabelType.all,
          destinations: [for (var i=0;i<5;i++) NavigationRailDestination(
            icon: Icon(GarageShell.icons[i]), label: Text(labels[i]))]),
        const VerticalDivider(width: 1), Expanded(child: body),
      ]) : body,
      bottomNavigationBar: wide ? null : NavigationBar(
        selectedIndex: _index, onDestinationSelected: _select,
        destinations: [for (var i=0;i<5;i++) NavigationDestination(
          key: Key('garage_tab_$i'), icon: Icon(GarageShell.icons[i]), label: labels[i])]),
    );
  });
}

class GarageHome extends StatelessWidget {
  const GarageHome({required this.workshopName, required this.onCalendar,
    required this.onOrders, required this.onRequests, required this.onFleetRequests,
    this.setupGuide, super.key});
  final String workshopName;
  final VoidCallback onCalendar, onOrders, onRequests, onFleetRequests;
  final Widget? setupGuide;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
    final actions = <(String, IconData, VoidCallback)>[
      ('calendarBays', Icons.calendar_month_outlined, onCalendar),
      ('ordersEstimates', Icons.build_outlined, onOrders),
      ('customerRequests', Icons.inbox_outlined, onRequests),
      ('fleetRequests', Icons.local_shipping_outlined, onFleetRequests),
    ];
    final columns = box.maxWidth >= 600 ? 2 : 1;
    final width = (box.maxWidth - 32 - (columns - 1) * 16) / columns;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text(workshopName, style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 4),
      Text('Flotaryx Garage', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 20),
      Wrap(spacing: 16, runSpacing: 16, children: [
        for (final action in actions) SizedBox(width: width, child: Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(key: Key('garage_home_${action.$1}'), onTap: action.$3,
            child: Padding(padding: const EdgeInsets.all(20), child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
                CircleAvatar(backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                  child: Icon(action.$2, color: Theme.of(context).colorScheme.onPrimaryContainer)),
                const SizedBox(height: 16),
                Text(GarageUiText.get(action.$1), style: Theme.of(context).textTheme.titleMedium),
              ]))),
        )),
      ]),
      if (setupGuide != null) ...[const SizedBox(height: 20), setupGuide!],
    ]);
  });
}
