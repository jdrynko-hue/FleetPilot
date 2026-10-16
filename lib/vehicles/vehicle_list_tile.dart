import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/formatters.dart';
import '../core/localization.dart';
import '../core/widgets.dart';
import '../data/models.dart';
import 'insurance_expiry.dart';

class VehicleListTile extends StatelessWidget {
  const VehicleListTile({
    required this.vehicle,
    required this.onOpen,
    this.onEdit,
    super.key,
  });

  final Vehicle vehicle;
  final VoidCallback onOpen;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onOpen,
      title: Text(vehicle.registration),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text([
            '${vehicle.make ?? ''} ${vehicle.model ?? ''}'.trim(),
            if (vehicle.currentDriverName != null) vehicle.currentDriverName!,
            '${formatMileage(vehicle.mileage)} mi',
          ].where((e) => e.isNotEmpty).join(' • ')),
          const SizedBox(height: 6),
          StatusPill(label: prettifyEnum(vehicle.status)),
          const SizedBox(height: 6),
          InsuranceExpiry(date: vehicle.insuranceExpiryDate),
        ],
      ),
      trailing: onEdit == null
          ? const Icon(Icons.chevron_right)
          : IconButton(
              tooltip: tr('edit'),
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
            ),
    );
  }
}
