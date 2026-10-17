import 'package:flutter/material.dart';

import 'consumer_booking_repository.dart';
import 'resource_calendar_repository.dart';
import 'booking_time_text.dart';
import 'booking_status_text.dart';
import 'garage_ui_text.dart';

/// Staging-only Garage scheduler: explicit bay selection and private calendar.
/// Kept outside production Fleet navigation until the ecosystem release.
class GarageResourceCalendarScreen extends StatefulWidget {
  const GarageResourceCalendarScreen({
    required this.loadResources,
    required this.loadRequests,
    required this.loadCalendar,
    required this.confirmSlot,
    this.embedded = false,
    super.key,
  });

  factory GarageResourceCalendarScreen.forRepositories({
    required GarageResourceCalendarRepository calendar,
    required GarageBookingRepository bookings,
    required String workspaceId,
    bool embedded = false,
    Key? key,
  }) => GarageResourceCalendarScreen(
    key: key, embedded: embedded,
    loadResources: () => calendar.resources(workspaceId),
    loadRequests: () => bookings.workshopInbox(workspaceId),
    loadCalendar: () => calendar.calendar(
      shopId: workspaceId, start: DateTime.now(),
      end: DateTime.now().add(const Duration(days: 7))),
    confirmSlot: calendar.confirmBooking,
  );

  final Future<List<GarageCalendarResource>> Function() loadResources;
  final Future<List<GarageBookingInboxItem>> Function() loadRequests;
  final Future<List<GarageCalendarAppointment>> Function() loadCalendar;
  final Future<String> Function(String bookingId, String resourceId) confirmSlot;
  final bool embedded;

  @override
  State<GarageResourceCalendarScreen> createState() =>
      _GarageResourceCalendarState();
}

class _GarageResourceCalendarState extends State<GarageResourceCalendarScreen> {
  List<GarageCalendarResource> _resources = const [];
  List<GarageBookingInboxItem> _requests = const [];
  List<GarageCalendarAppointment> _calendar = const [];
  final Map<String,String> _selection = {};
  bool _busy = true;
  bool _confirming = false;
  String? _error;
  int _sequence = 0;
  int _scope = 0;

  @override
  void initState() { super.initState(); _refresh(); }

  @override
  void didUpdateWidget(covariant GarageResourceCalendarScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.loadResources != widget.loadResources ||
        oldWidget.loadRequests != widget.loadRequests ||
        oldWidget.loadCalendar != widget.loadCalendar ||
        oldWidget.confirmSlot != widget.confirmSlot) {
      _scope++;
      _refresh();
    }
  }

  @override
  void dispose() { _scope++; _sequence++; super.dispose(); }

  Future<void> _refresh() async {
    if (!mounted) return;
    final sequence = ++_sequence;
    final loadResources = widget.loadResources;
    final loadRequests = widget.loadRequests;
    final loadCalendar = widget.loadCalendar;
    bool current() => mounted && sequence == _sequence;
    setState(() {
      _busy = true;
      _resources = const [];
      _requests = const [];
      _calendar = const [];
      _selection.clear(); // Never reuse a stale resource after permissions change.
      _error = null;
    });
    try {
      final resources = await loadResources();
      if (!current()) return;
      final requests = await loadRequests();
      if (!current()) return;
      final appointments = await loadCalendar();
      if (!current()) return;
      setState(() {
        _resources = List.unmodifiable(resources);
        _requests = List.unmodifiable(requests);
        _calendar = List.unmodifiable(appointments);
      });
    } catch (_) {
      if (!mounted || sequence != _sequence) return;
      setState(() {
        _resources = const [];
        _requests = const [];
        _calendar = const [];
        _error = GarageUiText.get('calendarLoadError');
      });
    } finally {
      if (mounted && sequence == _sequence) setState(() => _busy = false);
    }
  }

  Future<void> _accept(GarageBookingInboxItem request) async {
    final scope = _scope;
    final sequence = _sequence;
    final confirmSlot = widget.confirmSlot;
    final resourceId = _selection[request.id];
    if (_busy || _confirming || resourceId == null ||
        !_resources.any((resource) => resource.id == resourceId &&
            resource.active) ||
        request.status != GarageBookingStatus.requested) return;

    // Lock the intent synchronously, before the dialog's first frame.
    _confirming = true;
    bool? confirmed;
    try {
    confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(GarageUiText.get('calendarConfirmTitle')),
        content: Text(GarageUiText.get('calendarCheck')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context,false),
            child: Text(GarageUiText.get('quoteBack'))),
          FilledButton(
            key: const Key('calendar_confirm_action'),
            onPressed: () => Navigator.pop(context,true),
            child: Text(GarageUiText.get('inboxConfirm'))),
        ],
      ),
    );
    } finally {
      _confirming = false;
    }
    if (!mounted || scope != _scope || sequence != _sequence ||
        confirmed != true || _busy) return;
    setState(() {
      _busy = true;
      _requests = const []; // Sensitive details never remain after a failed RPC.
      _calendar = const [];
      _resources = const [];
      _selection.clear();
      _error = null;
    });
    var failed = false;
    try {
      final response = await confirmSlot(request.id,resourceId);
      if (response != 'confirmed') {
        throw const FormatException('Workshop booking was not confirmed');
      }
    } catch (_) {
      failed = true;
    } finally {
      if (mounted && scope == _scope) {
        final refresh = _refresh();
        final refreshSequence = _sequence;
        await refresh;
        if (mounted && scope == _scope && refreshSequence == _sequence && failed) {
          setState(() => _error = GarageUiText.get('calendarConfirmFailed'));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = _resources.where((r) => r.active).toList();
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
        backgroundColor: widget.embedded ? Theme.of(context).scaffoldBackgroundColor : null,
        foregroundColor: widget.embedded ? Theme.of(context).colorScheme.onSurface : null,
        title: Text(GarageUiText.get('calendarTitle')),
        actions: [
          IconButton(key: const Key('garage_calendar_refresh'),
            tooltip: GarageUiText.get('refresh'),
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh)),
        ],
      ),
      body: SafeArea(
        child: _busy ? const Center(child: CircularProgressIndicator()) :
          ListView(padding: const EdgeInsets.all(16), children: [
            Text(GarageUiText.get('calendarIntro')),
            if (_error != null)
              Text(_error!, key: const Key('garage_calendar_error')),
            const SizedBox(height: 14),
            Text(GarageUiText.get('calendarBaysTitle'),
              style: Theme.of(context).textTheme.titleLarge),
            for (final resource in _resources)
              ListTile(
                key: Key('garage_calendar_resource_' + resource.id),
                title: Text(resource.name),
                subtitle: Text(resource.active
                    ? GarageUiText.get('calendarActive')
                    : GarageUiText.get('calendarInactive')),
              ),
            if (active.isEmpty)
              Text(GarageUiText.get('calendarAddBay'),
                key: const Key('garage_calendar_no_resources')),
            const SizedBox(height: 14),
            Text(GarageUiText.get('calendarPending'),
              style: Theme.of(context).textTheme.titleLarge),
            for (final request in _requests)
              if (request.status == GarageBookingStatus.requested)
                Card(key: Key('garage_calendar_pending_' + request.id),
                  child: Padding(padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(request.customerName,
                          style: Theme.of(context).textTheme.titleMedium),
                        Text(bookingServiceLabel(request.service) + ' — ' + request.vehicleMake
                            + ' ' + request.vehicleModel),
                        Text(bookingLocalTimeLabel(request.startAt)),
                        DropdownButtonFormField<String>(
                          key: Key('garage_calendar_select_' + request.id),
                          value: _selection[request.id],
                          isExpanded: true,
                          decoration: InputDecoration(labelText:
                            GarageUiText.get('calendarSelectBay')),
                          items: active.map((resource) =>
                            DropdownMenuItem<String>(
                              value: resource.id, child: Text(resource.name,
                                maxLines: 1, overflow: TextOverflow.ellipsis)))
                            .toList(),
                          onChanged: active.isEmpty ? null : (id) =>
                            setState(() {
                              if (id == null) _selection.remove(request.id);
                              else _selection[request.id] = id;
                            }),
                        ),
                        FilledButton(
                          key: Key('garage_calendar_accept_' + request.id),
                          onPressed: _selection[request.id] == null
                              ? null : () => _accept(request),
                          child: Text(GarageUiText.get('calendarAccept'))),
                      ]))),
            const SizedBox(height: 14),
            Text(GarageUiText.get('calendarNextSeven'),
              style: Theme.of(context).textTheme.titleLarge),
            if (_calendar.isEmpty)
              Text(GarageUiText.get('calendarEmpty'),
                key: const Key('garage_calendar_empty')),
            for (final booking in _calendar)
              Card(key: Key('garage_calendar_appointment_' + booking.bookingId),
                child: ListTile(
                  title: Text(booking.customerName),
                  subtitle: Text(
                    bookingLocalTimeLabel(booking.startAt)
                    + ' — ' + (booking.resourceName ??
                        GarageUiText.get('calendarLegacy'))),
                  trailing: booking.status == 'cancellation_requested'
                      ? const Icon(Icons.hourglass_top)
                      : const Icon(Icons.check_circle_outline),
                )),
          ]),
      ),
    );
  }
}

/// Private in-app alerts: never SMS/email and no customer PII in payload.
class GarageBookingNotificationsScreen extends StatefulWidget {
  const GarageBookingNotificationsScreen({
    required this.load, required this.acknowledge, super.key,
  });
  factory GarageBookingNotificationsScreen.forRepository(
      GarageResourceCalendarRepository repository, {Key? key}) =>
      GarageBookingNotificationsScreen(key: key,
        load: repository.notifications,
        acknowledge: repository.acknowledge);

  final Future<List<GarageBookingNotice>> Function() load;
  final Future<bool> Function(String) acknowledge;

  @override
  State<GarageBookingNotificationsScreen> createState() =>
      _GarageBookingNotificationsState();
}

class _GarageBookingNotificationsState extends State<GarageBookingNotificationsScreen> {
  List<GarageBookingNotice> _notices = const [];
  bool _busy = true;
  String? _error;
  int _version = 0;
  int _scope = 0;

  @override
  void initState() { super.initState(); _refresh(); }
  @override
  void didUpdateWidget(covariant GarageBookingNotificationsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.load != widget.load ||
        oldWidget.acknowledge != widget.acknowledge) {
      _scope++;
      _refresh();
    }
  }
  @override
  void dispose() { _scope++; _version++; super.dispose(); }

  Future<void> _refresh() async {
    if (!mounted) return;
    final load = widget.load;
    final version = ++_version;
    setState(() {
      _busy = true; _notices = const []; _error = null;
    });
    try {
      final notices = await load();
      if (mounted && version == _version) {
        setState(() => _notices = List.unmodifiable(notices));
      }
    } catch (_) {
      if (mounted && version == _version) {
        setState(() => _error = 'noticeLoadFailed');
      }
    } finally {
      if (mounted && version == _version) setState(() => _busy = false);
    }
  }

  bool _current(int scope, int version) =>
      mounted && scope == _scope && version == _version;

  Future<void> _read(GarageBookingNotice notice, int scope, int version) async {
    if (!_current(scope, version) || _busy || !notice.unread ||
        !_notices.any((current) => current.id == notice.id && current.unread)) return;
    final acknowledge = widget.acknowledge;
    setState(() { _busy = true; _notices = const []; });
    var failed = false;
    try {
      if (!await acknowledge(notice.id)) {
        throw const FormatException('Read not acknowledged');
      }
    } catch (_) { failed = true; }
    if (mounted && scope == _scope) {
      final refresh = _refresh();
      final version = _version;
      await refresh;
      if (mounted && scope == _scope && version == _version && failed) setState(() =>
        _error = 'noticeReadUnconfirmed');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = _scope;
    final version = _version;
    return Scaffold(
    appBar: AppBar(title: Text(GarageUiText.get('notifications')),
      actions: [IconButton(key: const Key('garage_notifications_refresh'),
        tooltip: GarageUiText.get('refresh'),
        onPressed: _busy ? null : () {
          if (_current(scope, version)) _refresh();
        },
        icon: const Icon(Icons.refresh))]),
    body: SafeArea(child: _busy
      ? const Center(child: CircularProgressIndicator())
      : ListView(padding: const EdgeInsets.all(16), children: [
        Text(GarageUiText.get('noticeDisclaimer')),
        if (_error != null) Text(GarageUiText.get(_error!),
          key: const Key('garage_notifications_error')),
        if (_notices.isEmpty && _error == null) Text(GarageUiText.get('noticeEmpty'),
          key: const Key('garage_notifications_empty')),
        for (final notice in _notices) Card(
          key: Key('garage_notification_' + notice.id),
          child: Padding(padding: const EdgeInsets.all(12), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(notice.unread ? Icons.notifications_active_outlined
                  : Icons.notifications_none_outlined),
                const SizedBox(width: 8),
                Expanded(child: Text(bookingNoticeLabel(notice.event))),
              ]),
              Text(bookingLocalTimeLabel(notice.occurredAt)),
              if (notice.unread) Align(alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  key: Key('garage_notification_mark_' + notice.id),
                  onPressed: () => _read(notice, scope, version),
                  child: Text(GarageUiText.get('noticeMarkRead')))),
            ]))),
      ])),
  );
  }
}
