import 'package:flutter/material.dart';
import 'booking_status_text.dart';
import 'booking_time_text.dart';
import 'garage_ui_text.dart';

/// Review a preferred instant; never implies workshop availability/confirmation.
class BookingRequestReview extends StatelessWidget {
  const BookingRequestReview({required this.service, required this.when,
    required this.workshopZone, super.key});
  final String service;
  final DateTime when;
  final String workshopZone;

  @override
  Widget build(BuildContext context) => Card(
    key: const Key('booking_request_review'),
    child: Padding(padding: const EdgeInsets.all(16), child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('${GarageUiText.get('bookingService')}: ${bookingServiceLabel(service)}'),
        const SizedBox(height: 8),
        Text('${GarageUiText.get('bookingRequestTime')}: ${bookingLocalTimeLabel(when)}'),
        Text(GarageUiText.format('bookingWorkshopZone', {'zone': workshopZone})),
        const SizedBox(height: 8),
        Text(GarageUiText.get('bookingRequestDisclaimer')),
      ])),
  );
}
