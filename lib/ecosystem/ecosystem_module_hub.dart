import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../garage/booking_management_screens.dart';
import '../garage/booking_profile_screen.dart';
import '../garage/calendar_settings_screen.dart';
import '../garage/consumer_booking_repository.dart';
import '../garage/consumer_booking_screen.dart';
import '../garage/mechanic_jobs_repository.dart';
import '../garage/mechanic_work_screen.dart';
import '../garage/media_repository.dart';
import '../garage/resource_calendar_repository.dart';
import '../garage/resource_calendar_screen.dart';
import '../garage/workshop_quotes_screen.dart';
import '../garage/garage_ui_text.dart';
import '../garage/repair_requests_screen.dart';
import '../garage/bridge_connections_screen.dart';
import 'ecosystem_access.dart';
import 'customer_portal.dart';

/// Connects the existing repository-backed screens; no fixture IDs or mock data.
class EcosystemModuleHub extends StatelessWidget {
  const EcosystemModuleHub({required this.client,
    required this.destination, this.customerSearchFirst = false, this.customerCity, this.customerWorkshopId, super.key});
  final SupabaseClient client;
  final EcosystemDestination destination;
  final bool customerSearchFirst;
  final String? customerCity;
  final String? customerWorkshopId;

  @override
  Widget build(BuildContext context) {
    final bookings = GarageBookingRepository(client);
    final calendar = GarageResourceCalendarRepository(client);
    if (destination.module == EcosystemModule.mechanic) {
      return GarageMechanicWorkScreen.forRepository(
        jobs: GarageMechanicJobsRepository(client),
        media: GarageMediaRepository(client),
        workspaceId: destination.workspaceId!,
      );
    }
    final customer = destination.module == EcosystemModule.customer;
    if (customer) {
      return CustomerPortal(searchFirst: customerSearchFirst, pages: [
        (_) => GarageBookingSearchScreen.forRepository(bookings, initialCity: customerCity, initialWorkshopId: customerWorkshopId),
        (_) => GarageMyBookingsScreen.forRepository(bookings),
        (_) => GarageBookingNotificationsScreen.forRepository(calendar),
      ]);
    }
    final pages = <String, Widget Function()>{

        if (destination.canConfigure)
          GarageUiText.get('fleetConnections'): () =>
            GarageBridgeConnectionsScreen.forClient(client: client,
              scopeId: destination.workspaceId!, fleet: false),
        GarageUiText.get('calendarBays'): () =>
          GarageResourceCalendarScreen.forRepositories(calendar: calendar,
            bookings: bookings, workspaceId: destination.workspaceId!),
        GarageUiText.get('ordersEstimates'): () =>
          GarageWorkshopQuotesScreen.forClient(client: client,
            workspaceId: destination.workspaceId!),
        GarageUiText.get('fleetRequests'): () =>
          GarageRepairRequestsScreen.forClient(client: client,
            workspaceId: destination.workspaceId!, canAssign: destination.canConfigure),
        GarageUiText.get('customerRequests'): () =>
          GarageBookingWorkshopScreen.forRepository(repository: bookings,
            workspaceId: destination.workspaceId!),
        if (destination.canConfigure)
          GarageUiText.get('bookingProfile'): () =>
            GarageBookingProfileScreen.forRepository(repository: bookings,
              workspaceId: destination.workspaceId!),
        if (destination.canConfigure)
          GarageUiText.get('calendarSettings'): () =>
            GarageCalendarSettingsScreen.forRepository(repository: calendar,
              workspaceId: destination.workspaceId!),
    };
    return Scaffold(
      appBar: AppBar(title: Text(customer
        ? GarageUiText.get('workshopBookings')
        : destination.name!)),
      body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(padding: const EdgeInsets.all(20), children: [
          for (final page in pages.entries)
            Card(child: ListTile(title: Text(page.key),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(builder: (_) => page.value())))),
        ]),
      )),
    );
  }
}
