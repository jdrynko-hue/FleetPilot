import 'package:flutter/material.dart';

import '../company/business_review_alert.dart';
import '../core/localization.dart';
import '../data/models.dart';

enum _HeaderAction { manager, createFleet, refresh, signOut }

/// Keeps key actions reachable without overflowing a phone-width AppBar.
class FleetAppBar extends StatelessWidget implements PreferredSizeWidget {
  const FleetAppBar({
    required this.memberships,
    required this.selectedMembership,
    required this.canManage,
    required this.compact,
    required this.onFleetSelected,
    required this.onManagerPressed,
    required this.onNotificationsPressed,
    required this.onRefreshPressed,
    required this.onSignOutPressed,
    this.onCreateFleetPressed,
    this.businessReviewAlert = const BusinessReviewAlert(),
    super.key,
  });

  final List<CompanyMembership> memberships;
  final CompanyMembership selectedMembership;
  final bool canManage;
  final bool compact;
  final ValueChanged<String> onFleetSelected;
  final VoidCallback onManagerPressed;
  final VoidCallback onNotificationsPressed;
  final VoidCallback onRefreshPressed;
  final VoidCallback onSignOutPressed;
  final VoidCallback? onCreateFleetPressed;
  final Widget businessReviewAlert;
  bool get _canCreateFleet => onCreateFleetPressed != null &&
      (selectedMembership.role == 'owner' || selectedMembership.role == 'admin');

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  Widget _companySelector() {
    if (memberships.length <= 1) {
      return Text(
        selectedMembership.companyName,
        key: const Key('fleet_company_name'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white),
      );
    }

    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        key: const Key('fleet_company_selector'),
        value: selectedMembership.companyId,
        isExpanded: true,
        dropdownColor: const Color(0xFF102A43),
        style: const TextStyle(color: Colors.white),
        iconEnabledColor: Colors.white,
        selectedItemBuilder: compact
            ? (context) => memberships
                .map((member) => Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        member.companyName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ))
                .toList()
            : null,
        items: memberships
            .map((member) => DropdownMenuItem<String>(
                  value: member.companyId,
                  child: Text(
                    member.companyName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ))
            .toList(),
        onChanged: (companyId) {
          if (companyId != null) onFleetSelected(companyId);
        },
      ),
    );
  }

  Widget _brand() => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            'assets/branding/flotaryx_mark.png',
            width: compact ? 26 : 32,
            height: compact ? 26 : 32,
          ),
          const SizedBox(width: 8),
          if (!compact) const Text('Flotaryx'),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return AppBar(
      titleSpacing: compact ? 12 : null,
      title: compact
          ? Row(
              children: [
                _brand(),
                const SizedBox(width: 10),
                Expanded(child: _companySelector()),
              ],
            )
          : _brand(),
      actions: [
        if (!compact)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: Center(child: _companySelector()),
            ),
          ),
        businessReviewAlert,
        if (!compact && canManage)
          IconButton(
            tooltip: AppLocale.language.value == 'pl'
                ? 'Panel managera'
                : 'Manager control panel',
            icon: const Icon(Icons.admin_panel_settings_outlined),
            onPressed: onManagerPressed,
          ),
        IconButton(
          key: const Key('fleet_notifications'),
          tooltip: tr('notifications'),
          icon: const Icon(Icons.notifications_outlined),
          onPressed: onNotificationsPressed,
        ),
        if (compact)
          PopupMenuButton<_HeaderAction>(
            key: const Key('fleet_mobile_menu'),
            tooltip: tr('more'),
            icon: const Icon(Icons.more_vert),
            onSelected: (action) {
              switch (action) {
                case _HeaderAction.manager:
                  onManagerPressed();
                case _HeaderAction.createFleet:
                  onCreateFleetPressed?.call();
                case _HeaderAction.refresh:
                  onRefreshPressed();
                case _HeaderAction.signOut:
                  onSignOutPressed();
              }
            },
            itemBuilder: (_) => [
              if (_canCreateFleet)
                PopupMenuItem(key: const Key('fleet_menu_create'),
                  value: _HeaderAction.createFleet, child: Text(tr('create_fleet'))),
              if (canManage)
                PopupMenuItem(
                  key: const Key('fleet_menu_manager'),
                  value: _HeaderAction.manager,
                  child: Text(
                    AppLocale.language.value == 'pl'
                        ? 'Panel managera'
                        : 'Manager control panel',
                  ),
                ),
              PopupMenuItem(
                key: const Key('fleet_menu_refresh'),
                value: _HeaderAction.refresh,
                child: Text(tr('refresh')),
              ),
              PopupMenuItem(
                key: const Key('fleet_menu_signout'),
                value: _HeaderAction.signOut,
                child: Text(tr('sign_out')),
              ),
            ],
          )
        else ...[
          if (_canCreateFleet)
            IconButton(key: const Key('fleet_create_fleet'),
              tooltip: tr('create_fleet'), icon: const Icon(Icons.add_business_outlined),
              onPressed: onCreateFleetPressed),
          IconButton(
            tooltip: tr('refresh'),
            onPressed: onRefreshPressed,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: tr('sign_out'),
            onPressed: onSignOutPressed,
            icon: const Icon(Icons.logout),
          ),
        ],
      ],
    );
  }
}
