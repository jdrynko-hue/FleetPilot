/// Display the appointment in the viewer's local time zone, including the
/// offset/abbreviation at the appointment instant rather than today's zone.
String bookingLocalTimeLabel(DateTime startAt) {
  final local = startAt.toLocal();
  return '${local.toString().substring(0, 16)} (${local.timeZoneName})';
}
