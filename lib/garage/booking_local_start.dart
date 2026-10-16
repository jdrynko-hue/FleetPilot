/// Resolve a device-local wall clock without silently normalizing a DST gap or
/// choosing one of two repeated times. The caller must ask for another time.
DateTime? bookingLocalStart({
  required int year,
  required int month,
  required int day,
  required int hour,
  required int minute,
}) {
  bool matches(DateTime value) => value.year == year && value.month == month &&
      value.day == day && value.hour == hour && value.minute == minute;
  final local = DateTime(year, month, day, hour, minute);
  if (!matches(local)) return null;

  // Derive the transition size from the device zone instead of assuming that
  // every clock change lasts one hour (some zones change by 30 minutes).
  final before = local.subtract(const Duration(days: 1)).timeZoneOffset;
  final after = local.add(const Duration(days: 1)).timeZoneOffset;
  final change = before - after;
  if (change != Duration.zero &&
      (matches(local.add(change)) || matches(local.subtract(change)))) {
    return null;
  }
  return local;
}
