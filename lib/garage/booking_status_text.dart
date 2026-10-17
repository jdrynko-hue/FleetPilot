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

/// API identifiers remain stable; only user-facing service text is translated.
String bookingServiceLabel(String service, {String? language}) {
  final key = switch (service) {
    'diagnostics' => 'bookingServiceDiagnostics',
    'maintenance' => 'bookingServiceMaintenance',
    'brakes' => 'bookingServiceBrakes',
    'tyres' => 'bookingServiceTyres',
    'inspection' => 'bookingServiceInspection',
    'electrical' => 'bookingServiceElectrical',
    'bodywork' => 'bookingServiceBodywork',
    'other' => 'bookingServiceOther',
    _ => 'bookingServiceOther',
  };
  return GarageUiText.get(key, language: language);
}

/// Unknown event identifiers are never echoed into private notification UI.
String bookingNoticeLabel(String event, {String? language}) {
  final key = switch (event) {
    'requested' => 'bookingRequested',
    'confirmed' => 'bookingConfirmed',
    'declined' => 'bookingDeclined',
    'withdrawn' => 'bookingWithdrawn',
    'cancellation_requested' => 'bookingCancellationPending',
    'cancelled' => 'bookingCancelled',
    _ => 'noticeEventUnknown',
  };
  return GarageUiText.get(key, language: language);
}
