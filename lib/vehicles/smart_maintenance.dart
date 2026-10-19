/// Source-only Smart Maintenance domain. Fleet odometers are stored in miles.
/// UI conversions must never silently change the underlying odometer.
enum MaintenanceUnit { km, mi }

enum MaintenanceKind {
  oil, brakes, timingBelt, transmission, brakeFluid, coolant,
  filters, tyres, roadTax, other,
}

const maintenanceCodes = <MaintenanceKind, String>{
  MaintenanceKind.oil: 'oil',
  MaintenanceKind.brakes: 'brakes',
  MaintenanceKind.timingBelt: 'timing_belt',
  MaintenanceKind.transmission: 'transmission',
  MaintenanceKind.brakeFluid: 'brake_fluid',
  MaintenanceKind.coolant: 'coolant',
  MaintenanceKind.filters: 'filters',
  MaintenanceKind.tyres: 'tyres',
  MaintenanceKind.roadTax: 'road_tax',
  MaintenanceKind.other: 'other',
};

MaintenanceKind parseMaintenanceKind(String code) =>
    maintenanceCodes.entries.firstWhere((entry) => entry.value == code).key;

const defaultOilIntervalKm = 10000;
const kmPerMile = 1.609344;

int toMiles(int distance, MaintenanceUnit unit) {
  if (distance < 0) throw ArgumentError.value(distance, 'distance');
  return unit == MaintenanceUnit.mi ? distance : (distance / kmPerMile).round();
}

int fromMiles(int miles, MaintenanceUnit unit) {
  if (miles < 0) throw ArgumentError.value(miles, 'miles');
  return unit == MaintenanceUnit.mi ? miles : (miles * kmPerMile).round();
}

/// Distance remaining may be negative; it is never rounded before comparing
/// against the stored, authoritative mileage target.
int milesRemaining(int dueMiles, int currentMiles) => dueMiles - currentMiles;

int? nextServiceMiles({
  required int lastServiceMiles,
  required int? intervalDistance,
  required MaintenanceUnit unit,
}) {
  if (lastServiceMiles < 0) {
    throw ArgumentError.value(lastServiceMiles, 'lastServiceMiles');
  }
  if (intervalDistance == null) return null;
  if (intervalDistance <= 0 || intervalDistance > 500000) {
    throw ArgumentError.value(intervalDistance, 'intervalDistance');
  }
  return lastServiceMiles + toMiles(intervalDistance, unit);
}

/// Month boundaries are calendar based, not a fixed 30-day duration.
DateTime addCalendarMonths(DateTime date, int months) {
  if (months < 0 || months > 240) {
    throw ArgumentError.value(months, 'months');
  }
  final index = date.year * 12 + date.month - 1 + months;
  final year = index ~/ 12;
  final month = index % 12 + 1;
  final lastDay = DateTime.utc(year, month + 1, 0).day;
  final day = date.day < lastDay ? date.day : lastDay;
  return DateTime.utc(year, month, day);
}

enum MaintenanceAttention { unscheduled, normal, upcoming, due, overdue }

class MaintenancePlan {
  const MaintenancePlan({
    required this.id,
    required this.companyId,
    required this.vehicleId,
    required this.kind,
    required this.unit,
    required this.lastServiceMiles,
    required this.lastServiceDate,
    required this.active,
    this.cycle = 1,
    this.intervalDistance,
    this.intervalMonths,
    this.nextDueMiles,
    this.nextDueDate,
    this.notes,
  });

  final String id;
  final String companyId;
  final String vehicleId;
  final MaintenanceKind kind;
  final MaintenanceUnit unit;
  final int lastServiceMiles;
  final DateTime lastServiceDate;
  final bool active;
  final int cycle;
  final int? intervalDistance;
  final int? intervalMonths;
  final int? nextDueMiles;
  final DateTime? nextDueDate;
  final String? notes;

  factory MaintenancePlan.fromJson(Map<String, dynamic> json) =>
      MaintenancePlan(
        id: json['id'].toString(),
        companyId: json['company_id'].toString(),
        vehicleId: json['vehicle_id'].toString(),
        kind: parseMaintenanceKind(json['kind'].toString()),
        unit: json['distance_unit'] == 'km' ? MaintenanceUnit.km : MaintenanceUnit.mi,
        lastServiceMiles: (json['last_service_miles'] as num).toInt(),
        lastServiceDate: DateTime.parse(json['last_service_date'].toString()),
        active: json['active'] == true,
        cycle: (json['cycle'] as num?)?.toInt() ?? 1,
        intervalDistance: (json['interval_distance'] as num?)?.toInt(),
        intervalMonths: (json['interval_months'] as num?)?.toInt(),
        nextDueMiles: (json['next_due_miles'] as num?)?.toInt(),
        nextDueDate: json['next_due_date'] == null
            ? null : DateTime.parse(json['next_due_date'].toString()),
        notes: json['notes']?.toString(),
      );

  MaintenanceAttention attention(int currentMiles, DateTime today) {
    if (!active || (nextDueMiles == null && nextDueDate == null)) {
      return MaintenanceAttention.unscheduled;
    }
    final remaining = nextDueMiles == null ? null
        : nextDueMiles! - currentMiles;
    final days = nextDueDate == null ? null
        : DateTime.utc(nextDueDate!.year, nextDueDate!.month, nextDueDate!.day)
            .difference(DateTime.utc(today.year, today.month, today.day)).inDays;
    if ((remaining != null && remaining < 0) || (days != null && days < 0)) {
      return MaintenanceAttention.overdue;
    }
    if (remaining == 0 || days == 0) return MaintenanceAttention.due;
    if ((remaining != null && remaining <= toMiles(1000, MaintenanceUnit.km)) ||
        (days != null && days <= 30)) return MaintenanceAttention.upcoming;
    return MaintenanceAttention.normal;
  }
}

class MaintenanceAlert {
  const MaintenanceAlert({required this.planId, required this.cycle,
    required this.kind, required this.stage, required this.source,
    required this.createdAt, this.dueMiles, this.dueDate});
  final String planId;
  final int cycle;
  final MaintenanceKind kind;
  final String stage;
  final String source;
  final DateTime createdAt;
  final int? dueMiles;
  final DateTime? dueDate;

  factory MaintenanceAlert.fromJson(Map<String, dynamic> row) =>
      MaintenanceAlert(
        planId: row['plan_id'].toString(),
        cycle: (row['cycle'] as num).toInt(),
        kind: parseMaintenanceKind(row['kind'].toString()),
        stage: row['stage'].toString(),
        source: row['source'].toString(),
        createdAt: DateTime.parse(row['created_at'].toString()),
        dueMiles: (row['due_miles'] as num?)?.toInt(),
        dueDate: row['due_date'] == null ? null
            : DateTime.parse(row['due_date'].toString()),
      );
}

class MaintenanceHistory {
  const MaintenanceHistory({required this.kind, required this.completedDate,
    required this.completedMiles, required this.note});
  final MaintenanceKind kind;
  final DateTime completedDate;
  final int completedMiles;
  final String note;

  factory MaintenanceHistory.fromJson(Map<String, dynamic> row) =>
      MaintenanceHistory(
        kind: parseMaintenanceKind(row['kind'].toString()),
        completedDate: DateTime.parse(row['completed_date'].toString()),
        completedMiles: (row['completed_miles'] as num).toInt(),
        note: row['note']?.toString() ?? '',
      );
}

class MaintenanceOdometerReading {
  const MaintenanceOdometerReading(this.miles, this.date);
  final int miles;
  final DateTime date;
}

/// Estimated due date is informational only, not a promised appointment.
/// Missing, decreasing or inconsistent readings fail closed.
DateTime? estimateDueDate({
  required int remainingMiles,
  required MaintenanceOdometerReading older,
  required MaintenanceOdometerReading newer,
}) {
  if (remainingMiles <= 0 || older.miles < 0 ||
      newer.miles <= older.miles) return null;
  final hours = newer.date.toUtc().difference(older.date.toUtc()).inHours;
  if (hours < 24) return null;
  final milesPerDay = (newer.miles - older.miles) * 24 / hours;
  if (milesPerDay <= 0) return null;
  final daysAhead = (remainingMiles / milesPerDay).ceil();
  if (daysAhead > 3650) return null;
  final date = newer.date.toUtc();
  return DateTime.utc(date.year, date.month, date.day)
      .add(Duration(days: daysAhead));
}
