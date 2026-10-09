import 'localization.dart';

const vehicleStatuses = <String>[
  'available',
  'in_use',
  'workshop',
  'maintenance',
  'off_road',
  'sold',
];

const driverStatuses = <String>['active', 'inactive', 'holiday', 'suspended'];

const issuePriorities = <String>['low', 'medium', 'high', 'critical'];

const issueStatuses = <String>[
  'open',
  'booked',
  'in_progress',
  'resolved',
  'closed',
];

const repairStatuses = <String>[
  'planned',
  'booked',
  'in_progress',
  'ready',
  'completed',
  'cancelled',
];

const companyRoles = <String>['owner', 'admin', 'manager', 'viewer'];

bool canManageForRole(String role) =>
    role == 'owner' || role == 'admin' || role == 'manager';

String prettifyEnum(String value) {
  const translatable = {
    'available',
    'in_use',
    'workshop',
    'maintenance',
    'off_road',
    'sold',
    'active',
    'inactive',
    'holiday',
    'suspended',
    'low',
    'medium',
    'high',
    'critical',
    'open',
    'booked',
    'in_progress',
    'resolved',
    'closed',
    'planned',
    'ready',
    'completed',
    'cancelled',
    'owner',
    'admin',
    'manager',
    'viewer',
  };

  if (translatable.contains(value)) {
    return tr(value);
  }

  if (value.isEmpty) return value;

  return value
      .split('_')
      .map(
        (part) => part.isEmpty
            ? part
            : '${part[0].toUpperCase()}${part.substring(1)}',
      )
      .join(' ');
}
