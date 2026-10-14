import 'package:flutter/material.dart';

import '../core/localization.dart';
import 'consumer_booking_repository.dart';

/// Staging-only workshop request inbox. Not linked from production Fleet.
class GarageBookingWorkshopScreen extends StatefulWidget {
  const GarageBookingWorkshopScreen({
    required this.loadInbox, required this.respond,
    required this.confirmCancellation, super.key,
  });
  factory GarageBookingWorkshopScreen.forRepository({
    required GarageBookingRepository repository,
    required String workspaceId, Key? key,
  }) => GarageBookingWorkshopScreen(key: key,
    loadInbox: () => repository.workshopInbox(workspaceId),
    respond: (id, accept) => repository.respond(id, confirm: accept),
    confirmCancellation: repository.confirmCancellation);

  final Future<List<GarageBookingInboxItem>> Function() loadInbox;
  final Future<GarageBookingStatus> Function(String, bool) respond;
  final Future<void> Function(String) confirmCancellation;
  @override
  State<GarageBookingWorkshopScreen> createState() => _WorkshopBookingState();
}

class _WorkshopBookingState extends State<GarageBookingWorkshopScreen> {
  bool busy = true;
  List<GarageBookingInboxItem> items = const [];
  String? error;
  int version = 0;
  bool get pl => AppLocale.language.value == 'pl';
  String tr(String a, String b) => pl ? a : b;
  @override
  void initState() { super.initState(); refresh(); }
  @override
  void dispose() { version++; super.dispose(); }

  Future<void> refresh() async {
    if (!mounted) return;
    final current = ++version;
    setState(() { busy = true; items = const []; error = null; });
    try {
      final result = await widget.loadInbox();
      if (mounted && version == current) {
        setState(() => items = List.unmodifiable(result));
      }
    } catch (_) {
      if (mounted && version == current) {
        setState(() => error = tr('Nie można pobrać zgłoszeń.',
            'Could not load requests. Verify access and retry.'));
      }
    } finally {
      if (mounted && version == current) setState(() => busy = false);
    }
  }

  Future<void> action(GarageBookingInboxItem entry, String type) async {
    if (busy) return;
    final accepted = await showDialog<bool>(context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Potwierdź zmianę', 'Confirm action')),
        content: Text(type == 'accept'
          ? tr('Sprawdź grafik przed potwierdzeniem terminu.',
               'Check your workshop schedule before accepting.')
          : type == 'decline'
            ? tr('Odrzucić zapytanie?', 'Decline this request?')
            : tr('Anulować i zwolnić termin?', 'Cancel and release this slot?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c,false),
            child: Text(tr('Wróć', 'Back'))),
          FilledButton(key: const Key('workshop_booking_confirm'),
            onPressed: () => Navigator.pop(c,true),
            child: Text(tr('Potwierdź', 'Confirm'))),
        ],
      ));
    if (!mounted || accepted != true || busy) return;
    setState(() { busy = true; items = const []; error = null; });
    try {
      if (type == 'cancel') {
        await widget.confirmCancellation(entry.id);
      } else {
        final result = await widget.respond(entry.id,type == 'accept');
        if (result != (type == 'accept'
              ? GarageBookingStatus.confirmed
              : GarageBookingStatus.declined)) {
          throw const FormatException('Unexpected booking response');
        }
      }
    } catch (_) {
      if (mounted) setState(() => error = tr(
        'Nie potwierdzono zmiany. Odśwież i sprawdź status.',
        'Change not confirmed. Refresh and check the status.'));
    } finally {
      if (mounted) await refresh();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(tr('Zgłoszenia terminów', 'Appointment requests')),
      actions: [IconButton(key: const Key('workshop_booking_refresh'),
        onPressed: busy ? null : refresh, icon: const Icon(Icons.refresh))]),
    body: SafeArea(child: busy
      ? const Center(child: CircularProgressIndicator())
      : ListView(padding: const EdgeInsets.all(16), children: [
        Text(tr('To prośby, nie wolne terminy. Sprawdź kalendarz.',
                'These are requests, not available slots. Check your calendar.')),
        if (error != null) Text(error!,
          key: const Key('workshop_booking_error')),
        if (items.isEmpty) Text(tr('Brak nowych zgłoszeń.', 'No requests.'),
          key: const Key('workshop_booking_empty')),
        for (final entry in items) Card(
          key: Key('workshop_booking_item_' + entry.id),
          child: Padding(padding: const EdgeInsets.all(12), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(entry.customerName,
                style: Theme.of(context).textTheme.titleMedium),
              Text(entry.customerEmail),
              Text(entry.vehicleMake + ' ' + entry.vehicleModel),
              if (entry.registration != null) Text(entry.registration!),
              Text(entry.service + ': ' + entry.concern),
              Text(entry.startAt.toLocal().toString().substring(0,16)
                + ' (' + DateTime.now().timeZoneName + ')'),
              Text(entry.durationMinutes.toString() + ' min'),
              Text(entry.status.name,
                key: Key('workshop_booking_status_' + entry.id)),
              if (entry.status == GarageBookingStatus.requested)
                Wrap(spacing: 8, children: [
                  FilledButton(
                    key: Key('workshop_booking_accept_' + entry.id),
                    onPressed: () => action(entry,'accept'),
                    child: Text(tr('Potwierdź', 'Accept'))),
                  OutlinedButton(
                    key: Key('workshop_booking_decline_' + entry.id),
                    onPressed: () => action(entry,'decline'),
                    child: Text(tr('Odrzuć', 'Decline'))),
                ]),
              if (entry.status == GarageBookingStatus.cancellationRequested)
                OutlinedButton(
                  key: Key('workshop_booking_cancel_' + entry.id),
                  onPressed: () => action(entry,'cancel'),
                  child: Text(tr('Potwierdź anulowanie',
                      'Confirm cancellation'))),
            ]))),
      ])),
  );
}

/// Customer booking list; only signed-in caller's bookings via protected RPC.
class GarageMyBookingsScreen extends StatefulWidget {
  const GarageMyBookingsScreen({
    required this.loadBookings, required this.cancel, super.key,
  });
  factory GarageMyBookingsScreen.forRepository(
      GarageBookingRepository repository, {Key? key}) =>
    GarageMyBookingsScreen(key: key,
      loadBookings: repository.myRequests, cancel: repository.cancel);
  final Future<List<GarageBookingSummary>> Function() loadBookings;
  final Future<GarageBookingStatus> Function(String) cancel;
  @override
  State<GarageMyBookingsScreen> createState() => _MyBookingsState();
}

class _MyBookingsState extends State<GarageMyBookingsScreen> {
  List<GarageBookingSummary> items = const [];
  bool busy = true;
  String? error;
  int version = 0;
  bool get pl => AppLocale.language.value == 'pl';
  String tr(String a,String b) => pl ? a : b;
  @override
  void initState() { super.initState(); refresh(); }
  @override
  void dispose() { version++; super.dispose(); }

  Future<void> refresh() async {
    if (!mounted) return;
    final v = ++version;
    setState(() { busy = true; items = const []; error = null; });
    try {
      final result = await widget.loadBookings();
      if (mounted && v == version) {
        setState(() => items = List.unmodifiable(result));
      }
    } catch (_) {
      if (mounted && v == version) {
        setState(() => error = tr('Nie można pobrać rezerwacji.',
            'Could not load your requests.'));
      }
    } finally {
      if (mounted && v == version) setState(() => busy = false);
    }
  }

  String label(GarageBookingStatus status) => switch (status) {
    GarageBookingStatus.requested => tr('Prośba wysłana','Requested'),
    GarageBookingStatus.confirmed => tr('Potwierdzona','Confirmed'),
    GarageBookingStatus.declined => tr('Odrzucona','Declined'),
    GarageBookingStatus.withdrawn => tr('Wycofana','Withdrawn'),
    GarageBookingStatus.cancellationRequested =>
      tr('Czeka na anulowanie','Cancellation pending'),
    GarageBookingStatus.cancelled => tr('Anulowana','Cancelled'),
  };

  Future<void> withdraw(GarageBookingSummary entry) async {
    if (busy) return;
    final accepted = await showDialog<bool>(context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Anulować termin?', 'Cancel this appointment?')),
        content: Text(entry.isOnlyRequested
          ? tr('Wycofać prośbę?', 'Withdraw the request?')
          : tr('Poprosić warsztat o anulowanie?',
              'Request cancellation from the workshop?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c,false),
            child: Text(tr('Nie','No'))),
          FilledButton(key: const Key('customer_booking_confirm_cancel'),
            onPressed: () => Navigator.pop(c,true),
            child: Text(tr('Tak','Yes'))),
        ]));
    if (!mounted || accepted != true || busy) return;
    setState(() { busy = true; items = const []; error = null; });
    try {
      final result = await widget.cancel(entry.id);
      if (result != GarageBookingStatus.withdrawn &&
          result != GarageBookingStatus.cancellationRequested) {
        throw const FormatException('Unexpected cancellation state');
      }
    } catch (_) {
      if (mounted) setState(() => error = tr(
        'Nie można potwierdzić anulowania. Odśwież status.',
        'Cancellation unconfirmed. Refresh the status.'));
    } finally {
      if (mounted) await refresh();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr('Moje terminy','My appointments')),
      actions: [IconButton(key: const Key('customer_booking_refresh'),
        onPressed: busy ? null : refresh, icon: const Icon(Icons.refresh))]),
    body: SafeArea(child: busy
      ? const Center(child: CircularProgressIndicator())
      : ListView(padding: const EdgeInsets.all(16), children: [
        Text(tr('Termin jest ważny dopiero po potwierdzeniu przez warsztat.',
                'A slot is valid only after workshop confirmation.')),
        if (error != null) Text(error!,
          key: const Key('customer_booking_error')),
        if (items.isEmpty) Text(tr('Brak terminów.','No appointments.'),
          key: const Key('customer_booking_empty')),
        for (final entry in items) Card(
          key: Key('customer_booking_item_' + entry.id),
          child: Padding(padding: const EdgeInsets.all(12), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(entry.workshopName,
                style: Theme.of(context).textTheme.titleMedium),
              Text(entry.service),
              Text(entry.startAt.toLocal().toString().substring(0,16)
                + ' (' + DateTime.now().timeZoneName + ')'),
              Text(label(entry.status),
                key: Key('customer_booking_status_' + entry.id)),
              if (entry.status == GarageBookingStatus.requested ||
                  entry.status == GarageBookingStatus.confirmed)
                OutlinedButton(
                  key: Key('customer_booking_cancel_' + entry.id),
                  onPressed: () => withdraw(entry),
                  child: Text(tr('Anuluj','Cancel'))),
            ]))),
      ])),
  );
}
