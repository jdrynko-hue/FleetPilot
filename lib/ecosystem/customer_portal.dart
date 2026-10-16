import 'package:flutter/material.dart';
import '../garage/garage_ui_text.dart';

/// Each tab is built on demand; no private requests run for hidden tabs.
class CustomerPortal extends StatefulWidget {
  const CustomerPortal({required this.pages, this.searchFirst = false, super.key});
  final List<WidgetBuilder> pages;
  final bool searchFirst;
  @override
  State<CustomerPortal> createState() => _CustomerPortalState();
}

class _CustomerPortalState extends State<CustomerPortal> {
  late int _selected;
  @override
  void initState() {
    super.initState();
    _selected = widget.searchFirst ? 0 : 1;
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    body: KeyedSubtree(key: ValueKey(_selected),
      child: widget.pages[_selected](context)),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _selected,
      onDestinationSelected: (index) => setState(() => _selected = index),
      destinations: [
        NavigationDestination(key: const Key('customer_search_tab'),
          icon: const Icon(Icons.search), label: GarageUiText.get('findWorkshop')),
        NavigationDestination(key: const Key('customer_bookings_tab'),
          icon: const Icon(Icons.calendar_month_outlined), label: GarageUiText.get('myBookings')),
        NavigationDestination(key: const Key('customer_notifications_tab'),
          icon: const Icon(Icons.notifications_outlined), label: GarageUiText.get('notifications')),
      ],
    ),
  );
}
