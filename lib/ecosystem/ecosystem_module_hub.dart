import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_config.dart';
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
import '../garage/setup_guide.dart';
import '../garage/garage_shell.dart';
import '../garage/billing_screen.dart';
import '../garage/entitlement_repository.dart';
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
      Widget search({VoidCallback? onViewBookings}) => GarageBookingSearchScreen.forRepository(
        bookings, initialCity: customerCity, initialWorkshopId: customerWorkshopId,
        onViewBookings: onViewBookings);
      return CustomerPortal(searchFirst: customerSearchFirst,
        searchPage: (_, showBookings) => search(onViewBookings: showBookings), pages: [
        (_) => search(),
        (_) => GarageMyBookingsScreen.forRepository(bookings),
        (_) => GarageBookingNotificationsScreen.forRepository(calendar),
      ]);
    }
    final pages = <String, Widget Function()>{
        if (destination.canConfigure)
          GarageBillingScreen.text(0): () => GarageBillingScreen(
            workshopName: destination.name!, isOwner: destination.canConfigure,
            workspaceId: destination.workspaceId!,
            loadEntitlement: AppConfig.garageSandboxEntitlementEnabled
              ? () => GarageEntitlementRepository.forClient(client)
                .load(destination.workspaceId!)
              : null),
        if (destination.canConfigure)
          GarageUiText.get('fleetConnections'): () =>
            GarageBridgeConnectionsScreen.forClient(client: client,
              scopeId: destination.workspaceId!, fleet: false),
        GarageUiText.get('calendarBays'): () =>
          GarageResourceCalendarScreen.forRepositories(calendar: calendar,
            bookings: bookings, workspaceId: destination.workspaceId!, embedded: true),
        GarageUiText.get('ordersEstimates'): () =>
          GarageWorkshopQuotesScreen.forClient(client: client,
            workspaceId: destination.workspaceId!, embedded: true),
        GarageUiText.get('fleetRequests'): () =>
          GarageRepairRequestsScreen.forClient(client: client,
            workspaceId: destination.workspaceId!, canAssign: destination.canConfigure),
        GarageUiText.get('customerRequests'): () =>
          GarageBookingWorkshopScreen.forRepository(repository: bookings,
            workspaceId: destination.workspaceId!, embedded: true),
        if (destination.canConfigure)
          GarageUiText.get('bookingProfile'): () =>
            GarageBookingProfileScreen.forRepository(repository: bookings,
              workspaceId: destination.workspaceId!, country: destination.country),
        if (destination.canConfigure)
          GarageUiText.get('calendarSettings'): () =>
            GarageCalendarSettingsScreen.forRepository(repository: calendar,
              workspaceId: destination.workspaceId!),
    };
    VoidCallback open(Widget Function() page) => () {
      Navigator.of(context).push<void>(MaterialPageRoute<void>(builder: (_) => page()));
    };
    final tabs = ['calendarBays', 'ordersEstimates', 'customerRequests'];
    return GarageShell(scopeId: '${destination.workspaceId}:${destination.canConfigure}',
      workshopName: destination.name!, pages: [
        (context) => GarageHome(workshopName: destination.name!,
          onCalendar: () => GarageShell.selectTab(context, 1),
          onOrders: () => GarageShell.selectTab(context, 2),
          onRequests: () => GarageShell.selectTab(context, 3),
          onFleetRequests: open(pages[GarageUiText.get('fleetRequests')]!),
          setupGuide: destination.canConfigure ? GarageSetupGuide(
            openProfile: open(pages[GarageUiText.get('bookingProfile')]!),
            openCalendar: open(pages[GarageUiText.get('calendarSettings')]!),
            openRequests: () => GarageShell.selectTab(context, 3),
          ) : null),
        for (final tab in tabs) (_) => pages[GarageUiText.get(tab)]!(),
        (_) => ListView(padding: const EdgeInsets.all(16), children: [
          for (final page in pages.entries.where((entry) =>
              !tabs.any((tab) => GarageUiText.get(tab) == entry.key)))
            Padding(padding: const EdgeInsets.only(bottom: 12),
              child: Card(child: ListTile(title: Text(page.key),
                trailing: const Icon(Icons.chevron_right), onTap: open(page.value)))),
        ]),
      ]);
  }
}
