import '../data/models.dart';

enum FleetExportType { vehicles, repairs, issues, drivers, costs }

// Spreadsheet applications may interpret untrusted cells as formulas.
// Neutralize spreadsheet formula prefixes before CSV escaping.
String escapeFleetCsvValue(Object? value) {
  if (value == null) return '';
  var cell = value.toString();
  if (value is String) {
    final trimmed = cell.trimLeft();
    if (trimmed.isNotEmpty &&
        ('=+-@'.contains(trimmed[0]) ||
            trimmed.codeUnitAt(0) == 0x09 ||
            trimmed.codeUnitAt(0) == 0x0d ||
            trimmed.codeUnitAt(0) == 0x0a)) {
      cell = "'$trimmed";
    }
  }
  if (cell.contains(',') ||
      cell.contains('"') ||
      cell.contains('\n') ||
      cell.contains('\r')) {
    return '"${cell.replaceAll('"', '""')}"';
  }
  return cell;
}

String encodeFleetCsv(List<List<Object?>> rows) {
  // UTF-8 BOM ensures Excel displays Polish and other Unicode characters.
  return '\uFEFF${rows.map((row) => row.map(escapeFleetCsvValue).join(',')).join('\r\n')}\r\n';
}

String _date(DateTime? value) =>
    value == null ? '' : value.toIso8601String().substring(0, 10);

String _amount(double value) => value.toStringAsFixed(2);

DateTime? _repairDate(Repair r) => r.completedAt ?? r.startedAt ?? r.bookedAt;

List<List<Object?>> buildFleetExportRows({
  required FleetExportType type,
  required String currency,
  required List<Vehicle> vehicles,
  required List<Repair> repairs,
  required List<FleetIssue> issues,
  required List<Driver> drivers,
}) {
  switch (type) {
    case FleetExportType.vehicles:
      return <List<Object?>>[
        <Object?>[
          'Registration',
          'Make',
          'Model',
          'Year',
          'VIN',
          'Mileage',
          'Status',
          'Driver',
          'Inspection type',
          'Inspection due',
          'Service due',
          'Service mileage',
          'Insurance expiry',
          'Notes',
        ],
        for (final vehicle in vehicles)
          <Object?>[
            vehicle.registration,
            vehicle.make,
            vehicle.model,
            vehicle.year,
            vehicle.vin,
            vehicle.mileage,
            vehicle.status,
            vehicle.currentDriverName,
            vehicle.inspectionType,
            _date(vehicle.inspectionDueDate),
            _date(vehicle.serviceDueDate),
            vehicle.serviceDueMileage,
            _date(vehicle.insuranceExpiryDate),
            vehicle.notes,
          ],
      ];

    case FleetExportType.repairs:
      return <List<Object?>>[
        <Object?>[
          'Registration',
          'Repair',
          'Status',
          'Garage',
          'Booked',
          'Started',
          'Completed',
          'Mileage',
          'Parts cost',
          'Labour cost',
          'Other cost',
          'Total cost',
          'Currency',
          'Invoice reference',
          'Notes',
        ],
        for (final repair in repairs)
          <Object?>[
            repair.registration,
            repair.description,
            repair.status,
            repair.garageName,
            _date(repair.bookedAt),
            _date(repair.startedAt),
            _date(repair.completedAt),
            repair.mileageIn,
            _amount(repair.partsCost),
            _amount(repair.labourCost),
            _amount(repair.otherCost),
            _amount(repair.totalCost),
            currency,
            repair.invoiceReference,
            repair.notes,
          ],
      ];

    case FleetExportType.issues:
      return <List<Object?>>[
        <Object?>[
          'Registration',
          'Issue',
          'Priority',
          'Status',
          'Reported',
          'Resolved',
          'Mileage',
          'Description',
          'Notes',
        ],
        for (final issue in issues)
          <Object?>[
            issue.registration,
            issue.title,
            issue.priority,
            issue.status,
            _date(issue.reportedAt),
            _date(issue.resolvedAt),
            issue.mileageAtReport,
            issue.description,
            issue.notes,
          ],
      ];

    case FleetExportType.drivers:
      return <List<Object?>>[
        <Object?>[
          'Name',
          'Status',
          'Employee reference',
          'Phone',
          'Email',
          'Notes',
        ],
        for (final driver in drivers)
          <Object?>[
            driver.name,
            driver.status,
            driver.employeeReference,
            driver.phone,
            driver.email,
            driver.notes,
          ],
      ];

    case FleetExportType.costs:
      final today = DateTime.now();
      double costSince(int days) {
        final cutoff = today.subtract(Duration(days: days));
        return repairs
            .where((repair) {
              final date = _repairDate(repair);
              return date != null && !date.isBefore(cutoff);
            })
            .fold<double>(0, (sum, repair) => sum + repair.totalCost);
      }

      final cutoff365 = today.subtract(const Duration(days: 365));
      final costByVehicle = <String, double>{};
      final names = <String, String>{};
      for (final repair in repairs) {
        final date = _repairDate(repair);
        if (date == null || date.isBefore(cutoff365)) continue;
        costByVehicle.update(
          repair.vehicleId,
          (previous) => previous + repair.totalCost,
          ifAbsent: () => repair.totalCost,
        );
        names[repair.vehicleId] = repair.registration ?? repair.vehicleId;
      }
      final ranking = costByVehicle.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      return <List<Object?>>[
        <Object?>['Group', 'Label', 'Value', 'Currency'],
        <Object?>['Summary', 'Last 30 days', _amount(costSince(30)), currency],
        <Object?>['Summary', 'Last 90 days', _amount(costSince(90)), currency],
        <Object?>[
          'Summary',
          'Last 365 days',
          _amount(costSince(365)),
          currency,
        ],
        for (final entry in ranking)
          <Object?>[
            'Vehicle / last 365 days',
            names[entry.key],
            _amount(entry.value),
            currency,
          ],
      ];
  }
}
