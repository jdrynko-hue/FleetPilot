import 'package:flutter/material.dart';
import '../garage/garage_ui_text.dart';

enum PortalEntry { fleet, garage, customer }

PortalEntry? portalEntryFromUri(Uri uri) => switch (uri.queryParameters['portal']) {
  'fleet' => PortalEntry.fleet,
  'garage' => PortalEntry.garage,
  'customer' || 'search' => PortalEntry.customer,
  _ => null,
};

/// Navigation intent only. Memberships and server permissions grant access.
class PortalEntryPicker extends StatelessWidget {
  const PortalEntryPicker({required this.selected, required this.onSelected,
    this.onFindWorkshop, super.key});
  final PortalEntry? selected;
  final ValueChanged<PortalEntry>? onSelected;
  final VoidCallback? onFindWorkshop;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(GarageUiText.get('chooseModule')),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final entry in PortalEntry.values)
          ChoiceChip(key: Key('portal_${entry.name}'),
            label: Text(switch (entry) {
              PortalEntry.fleet => 'Flotaryx Fleet',
              PortalEntry.garage => 'Flotaryx Garage',
              PortalEntry.customer => GarageUiText.get('myBookings'),
            }),
            selected: selected == entry,
            onSelected: onSelected == null ? null : (_) => onSelected!(entry)),
      ]),
      if (onFindWorkshop != null)
        OutlinedButton.icon(key: const Key('portal_find_workshop'),
          onPressed: onFindWorkshop, icon: const Icon(Icons.search),
          label: Text(GarageUiText.get('findWorkshop'))),
      const SizedBox(height: 12),
      Text(selected == PortalEntry.garage ? 'Flotaryx Garage' :
        selected == PortalEntry.customer ? GarageUiText.get('myBookings') :
        'Flotaryx Fleet', style: Theme.of(context).textTheme.titleMedium),
    ],
  );
}
