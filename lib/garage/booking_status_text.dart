import 'consumer_booking_repository.dart';
import 'garage_ui_text.dart';

/// Display labels only. Booking authorization and transitions use typed states.
String bookingStatusLabel(GarageBookingStatus status, {String? language}) {
  final key = switch (status) {
    GarageBookingStatus.requested => 'bookingRequested',
    GarageBookingStatus.confirmed => 'bookingConfirmed',
    GarageBookingStatus.declined => 'bookingDeclined',
    GarageBookingStatus.withdrawn => 'bookingWithdrawn',
    GarageBookingStatus.cancellationRequested => 'bookingCancellationPending',
    GarageBookingStatus.cancelled => 'bookingCancelled',
  };
  return GarageUiText.get(key, language: language);
}
