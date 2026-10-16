import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/localization.dart';

/// Vehicle deadlines are calendar dates, not instants. UTC arithmetic on their
/// components avoids losing a day across daylight-saving clock changes.
int calendarDaysUntil(DateTime date, DateTime today) => DateTime.utc(
  date.year,
  date.month,
  date.day,
).difference(DateTime.utc(today.year, today.month, today.day)).inDays;

bool insuranceNeedsAttention(DateTime? expiry, DateTime today) =>
    expiry != null && calendarDaysUntil(expiry, today) <= 30;

/// Calendar-day thresholds for a future server-side reminder dispatcher.
/// An overdue policy stays visible in the app but must not trigger an
/// unbounded daily email sequence.
bool insuranceReminderDue(DateTime? expiry, DateTime today) =>
    expiry != null && const {30, 14, 7, 1, 0}.contains(calendarDaysUntil(expiry, today));

/// Stable per-vehicle, per-policy reminder identity for idempotent delivery.
/// A renewed policy receives a different key even if its vehicle ID is unchanged.
/// A backend must enforce uniqueness on this key atomically; generating the
/// same string twice does not itself prevent duplicate notifications.
String insuranceReminderKey({
  required String vehicleId,
  required DateTime expiry,
  required int daysBefore,
}) {
  if (vehicleId.trim().isEmpty) {
    throw ArgumentError.value(vehicleId, 'vehicleId', 'Vehicle ID is required');
  }
  if (!const {30, 14, 7, 1, 0}.contains(daysBefore)) {
    throw ArgumentError.value(daysBefore, 'daysBefore', 'Unsupported reminder stage');
  }
  final date = '${expiry.year.toString().padLeft(4, '0')}-'
      '${expiry.month.toString().padLeft(2, '0')}-'
      '${expiry.day.toString().padLeft(2, '0')}';
  return 'insurance:${Uri.encodeComponent(vehicleId)}:$date:$daysBefore';
}

class InsuranceExpiry extends StatelessWidget {
  const InsuranceExpiry({required this.date, this.today, super.key});

  final DateTime? date;
  final DateTime? today;

  @override
  Widget build(BuildContext context) {
    final expiry = date;
    final days = expiry == null
        ? null
        : calendarDaysUntil(expiry, today ?? DateTime.now());
    final status = days == null
        ? tr('insurance_date_missing')
        : days < 0
        ? tr('notification_overdue')
        : days == 0
        ? tr('notification_due_today')
        : days <= 30
        ? trf('insurance_days_remaining', {'days': days})
        : null;
    final colors = Theme.of(context).colorScheme;
    final urgent = days != null && days <= 7;
    final approaching = days != null && days <= 30;
    final color = urgent
        ? colors.error
        : approaching
        ? colors.onTertiaryContainer
        : colors.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: urgent
            ? colors.errorContainer
            : approaching
            ? colors.tertiaryContainer
            : null,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shield_outlined, size: 18, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${tr('insurance_expiry')}: ${expiry == null ? status : formatDate(expiry)}'
              '${expiry != null && status != null ? ' • $status' : ''}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: color,
                fontWeight: approaching ? FontWeight.w600 : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
