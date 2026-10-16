import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/localization.dart';
import '../garage/booking_management_screens.dart';
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

/// Connects the existing repository-backed screens; no fixture IDs or mock data.
class EcosystemModuleHub extends StatelessWidget {
  const EcosystemModuleHub({required this.client,
    required this.destination, super.key});
  final SupabaseClient client;
  final EcosystemDestination destination;

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
    final pages = <String, Widget Function()>{
      if (customer) ...{
        GarageUiText.get('findWorkshop'): () =>
          GarageBookingSearchScreen.forRepository(bookings),
        GarageUiText.get('myBookings'): () =>
          GarageMyBookingsScreen.forRepository(bookings),
        GarageUiText.get('notifications'): () =>
          GarageBookingNotificationsScreen.forRepository(calendar),
      } else ...{
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
          GarageUiText.get('calendarSettings'): () =>
            GarageCalendarSettingsScreen.forRepository(repository: calendar,
              workspaceId: destination.workspaceId!),
      },
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
