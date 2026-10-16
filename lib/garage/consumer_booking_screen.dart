import 'package:flutter/material.dart';

import 'consumer_booking_repository.dart';
import 'booking_status_text.dart';
import 'booking_time_text.dart';
import 'booking_local_start.dart';
import 'garage_ui_text.dart';

typedef BookingSearch = Future<List<GarageBookingWorkshop>> Function({String? city});
typedef BookingSubmit = Future<String> Function({
  required String workspaceId, required String customerName,
  required String vehicleMake, required String vehicleModel,
  required String service, required String concern,
  required DateTime desiredStart, required String requestKey, String? registration,
});
typedef BookingTimePicker = Future<DateTime?> Function(BuildContext context);

/// Staging only. No production Fleet navigation or guaranteed availability.
class GarageBookingSearchScreen extends StatefulWidget {
  const GarageBookingSearchScreen({
    required this.search, required this.submit,
    this.pickTime = pickBookingTime, this.beforeRequest, this.onWorkshopSelected,
    this.initialCity, this.initialWorkshopId, super.key,
  });

  factory GarageBookingSearchScreen.forRepository(
    GarageBookingRepository repository, {Key? key, String? initialCity, String? initialWorkshopId}) =>
      GarageBookingSearchScreen(
        key: key, initialCity: initialCity, initialWorkshopId: initialWorkshopId, search: repository.findWorkshops,
        submit: repository.request);

  final BookingSearch search;
  final BookingSubmit submit;
  final BookingTimePicker pickTime;
  final Future<bool> Function()? beforeRequest;
  final void Function(String workspaceId, String city)? onWorkshopSelected;
  final String? initialCity;
  final String? initialWorkshopId;

  @override
  State<GarageBookingSearchScreen> createState() => _GarageBookingSearchState();
}

class _GarageBookingSearchState extends State<GarageBookingSearchScreen> {
  final _city = TextEditingController();
  List<GarageBookingWorkshop> _shops = const [];
  String _serviceFilter = '';
  bool _searched = false;
  int _scope = 0;
  bool _busy = false;
  bool _opening = false;
  String? _error;
  int _generation = 0;

  List<GarageBookingWorkshop> get _visibleShops => _serviceFilter.isEmpty
      ? _shops : _shops.where((shop) => shop.services.contains(_serviceFilter)).toList();

  @override
  void initState() {
    super.initState();
    final city = widget.initialCity?.trim();
    if (city != null && city.length <= 80) _city.text = city;
    if (widget.initialWorkshopId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _search();
      });
    }
  }

  @override
  void didUpdateWidget(covariant GarageBookingSearchScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.search != widget.search ||
        oldWidget.submit != widget.submit ||
        oldWidget.pickTime != widget.pickTime ||
        oldWidget.beforeRequest != widget.beforeRequest ||
        oldWidget.onWorkshopSelected != widget.onWorkshopSelected ||
        oldWidget.initialCity != widget.initialCity ||
        oldWidget.initialWorkshopId != widget.initialWorkshopId) {
      // Repository callbacks define the authenticated directory scope.
      // Invalidate old in-flight results and never show another scope's shops.
      _generation++;
      _scope++;
      _shops = const [];
      _searched = false;
      _serviceFilter = '';
      _city.clear();
      _error = null;
      _busy = false;
      _opening = false;
    }
  }

  @override
  void dispose() {
    _generation++;
    _city.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (_busy) return;
    final city = _city.text.trim();
    if (city.isNotEmpty && city.length < 2) {
      setState(() {
        _shops = const []; _searched = false;
        _error = 'bookingSearchShortCity';
      });
      return;
    }
    final gen = ++_generation;
    _opening = false;
    final search = widget.search;
    setState(() { _busy = true; _shops = const []; _searched = false; _error = null; });
    try {
      final result = await search(city: city.isEmpty ? null : city);
      if (!mounted || gen != _generation) return;
      setState(() {
        // The guest selection is navigation intent only. Re-query public
        // listings after login; never reuse a stale workshop/profile object.
        final ordered = [...result];
        final selected = ordered.indexWhere((shop) => shop.workspaceId == widget.initialWorkshopId);
        if (selected > 0) ordered.insert(0, ordered.removeAt(selected));
        _shops = List.unmodifiable(ordered);
        _searched = true;
        if (result.isEmpty) {
          _error = 'bookingSearchEmpty';
        }
      });
    } catch (_) {
      if (!mounted || gen != _generation) return;
      setState(() {
        _shops = const [];
        _searched = false;
        _error = 'bookingSearchFailed';
      });
    } finally {
      if (mounted && gen == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _open(GarageBookingWorkshop shop) async {
    if (_busy || _opening) return;
    final generation = _generation;
    var handedOff = false;
    setState(() => _opening = true);
    try {
      widget.onWorkshopSelected?.call(shop.workspaceId, _city.text.trim());
      final allowed = widget.beforeRequest == null || await widget.beforeRequest!();
      if (!mounted || generation != _generation) return;
      if (!allowed) {
        // Login handoff may still be animating out. Keep this intent locked;
        // only an explicit new search or a new scope can start another one.
        handedOff = true;
        return;
      }
      await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => GarageBookingRequestScreen(
          shop: shop, submit: widget.submit, pickTime: widget.pickTime),
      ));
      if (mounted && generation == _generation) await _search();
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error = 'bookingSearchFailed');
      }
    } finally {
      if (mounted && generation == _generation && !handedOff) {
        setState(() => _opening = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(GarageUiText.get('findWorkshop'))),
    body: SafeArea(child: ListView(padding: const EdgeInsets.all(16),
      children: [
        Text(GarageUiText.get('bookingSearchHint'),
            key: const Key('booking_not_guaranteed')),
        const SizedBox(height: 16),
        TextField(key: const Key('booking_search_city'),
          controller: _city, maxLength: 80,
          onSubmitted: (_) => _search(),
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            labelText: GarageUiText.get('bookingSearchCity'))),
        KeyedSubtree(key: ValueKey(_scope), child: DropdownButtonFormField<String>(
          key: const Key('booking_search_service'),
          initialValue: _serviceFilter,
          isExpanded: true,
          decoration: InputDecoration(border: const OutlineInputBorder(),
            labelText: GarageUiText.get('bookingSearchService')),
          items: [
            DropdownMenuItem(value: '', child: Text(
              GarageUiText.get('bookingSearchAllServices'), overflow: TextOverflow.ellipsis)),
            for (final code in GarageBookingService.values)
              DropdownMenuItem(value: code, child: Text(
                bookingServiceLabel(code), overflow: TextOverflow.ellipsis)),
          ],
          onChanged: _busy ? null : (value) => setState(() => _serviceFilter = value ?? ''),
        )),
        const SizedBox(height: 12),
        FilledButton(key: const Key('booking_search_submit'),
          onPressed: _busy ? null : _search,
          child: Text(GarageUiText.get('bookingSearchAction'))),
        if (_busy) const Center(child: CircularProgressIndicator()),
        if (_error != null) Text(GarageUiText.get(_error!),
          key: const Key('booking_search_error')),
        if (_searched && _shops.isNotEmpty) ...[
          Text(GarageUiText.get('bookingSearchLimitHint'),
            key: const Key('booking_search_limit_hint')),
          if (_visibleShops.isEmpty)
            Text(GarageUiText.get('bookingSearchNoService'),
              key: const Key('booking_search_no_service'))
          else
            Text(GarageUiText.format('bookingSearchCount', {'count': _visibleShops.length}),
              key: const Key('booking_search_count')),
        ],
        for (final shop in _visibleShops) Card(
          key: Key('booking_shop_${shop.workspaceId}'),
          shape: shop.workspaceId == widget.initialWorkshopId
            ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2)) : null,
          child: Padding(padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(shop.name, style: Theme.of(context).textTheme.titleMedium),
                Text('${shop.city}, ${shop.country}'),
                Text(shop.services.map((service) => bookingServiceLabel(service)).join(', ')),
                Text(GarageUiText.format('bookingWorkshopZone', {'zone': shop.timeZone})),
                OutlinedButton(key: Key('booking_open_${shop.workspaceId}'),
                  onPressed: _busy || _opening ? null : () => _open(shop),
                  child: Text(GarageUiText.get('bookingRequestTime'))),
              ]),
          ),
        ),
      ]),
    ),
  );
}

/// Calendar/time picker interprets the selection in the user's device zone,
/// NEVER claims the workshop's available calendar slots.
Future<DateTime?> pickBookingTime(BuildContext context) async {
  final now = DateTime.now();
  final first = now.add(const Duration(hours: 2));
  final day = await showDatePicker(context: context,
    firstDate: first,
    lastDate: now.add(const Duration(days: 90)),
    initialDate: first.add(const Duration(days: 1)));
  if (day == null || !context.mounted) return null;
  final time = await showTimePicker(context: context,
    initialTime: const TimeOfDay(hour: 10, minute: 0));
  if (time == null || !context.mounted) return null;
  final selected = bookingLocalStart(year: day.year, month: day.month,
      day: day.day, hour: time.hour, minute: time.minute);
  if (selected == null) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
      GarageUiText.get('bookingInvalidLocalTime'))));
  }
  return selected;
}

class GarageBookingRequestScreen extends StatefulWidget {
  const GarageBookingRequestScreen({
    required this.shop, required this.submit,
    this.pickTime = pickBookingTime, super.key,
  });
  final GarageBookingWorkshop shop;
  final BookingSubmit submit;
  final BookingTimePicker pickTime;

  @override
  State<GarageBookingRequestScreen> createState() => _GarageBookingRequestState();
}

class _GarageBookingRequestState extends State<GarageBookingRequestScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _make = TextEditingController();
  final _model = TextEditingController();
  final _registration = TextEditingController();
  final _concern = TextEditingController();
  String? _service;
  DateTime? _when;
  bool _busy = false;
  String? _error;
  bool _sent = false;
  bool _uncertain = false;
  int _generation = 0;
  String _requestKey = newBookingRequestKey();

  @override
  void didUpdateWidget(covariant GarageBookingRequestScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.shop.workspaceId != widget.shop.workspaceId ||
        oldWidget.submit != widget.submit ||
        oldWidget.pickTime != widget.pickTime) {
      // Never reuse private customer details, service selection, or
      // submission outcome for a different workshop/account scope.
      _generation++;
      _busy = false;
      _sent = false;
      _uncertain = false;
      _requestKey = newBookingRequestKey();
      _error = null;
      _service = null;
      _when = null;
      for (final controller in
          [_name, _make, _model, _registration, _concern]) {
        controller.clear();
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    for (final c in [_name, _make, _model, _registration, _concern]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _field(String key, String label, TextEditingController controller,
      {int limit = 120, int min = 2, bool optional = false, int lines = 1}) =>
    TextFormField(key: Key(key), controller: controller,
      maxLength: limit, maxLines: lines,
      decoration: InputDecoration(labelText: label,
        border: const OutlineInputBorder()),
      validator: (value) {
        final n = value?.trim().length ?? 0;
        return (optional && n == 0) || (n >= min && n <= limit)
          ? null : GarageUiText.get('bookingInvalidField');
      });

  Future<void> _pick() async {
    if (_busy || _sent) return;
    final gen = _generation;
    final pickTime = widget.pickTime;
    // A rejected or cancelled replacement must not leave a previous time
    // ready to submit as though the new selection had succeeded.
    setState(() { _when = null; _error = null; });
    final when = await pickTime(context);
    if (when != null && mounted && gen == _generation) {
      setState(() { _when = when; _error = null; });
    }
  }

  Future<void> _send() async {
    if (_busy || _sent || _uncertain ||
        !(_form.currentState?.validate() ?? false)) return;
    final when = _when;
    if (when == null ||
        when.isBefore(DateTime.now().add(const Duration(hours: 1))) ||
        when.isAfter(DateTime.now().add(const Duration(days: 90)))) {
      setState(() => _error = 'bookingChooseWithin90Days');
      return;
    }
    final gen = ++_generation;
    final submit = widget.submit;
    final workspaceId = widget.shop.workspaceId;
    setState(() { _busy = true; _error = null; });
    try {
      await submit(
        workspaceId: workspaceId,
        requestKey: _requestKey,
        customerName: _name.text.trim(),
        vehicleMake: _make.text.trim(),
        vehicleModel: _model.text.trim(),
        registration: _registration.text.trim().isEmpty
            ? null : _registration.text.trim(),
        service: _service!,
        concern: _concern.text.trim(),
        desiredStart: when,
      );
      if (mounted && gen == _generation) setState(() => _sent = true);
    } catch (_) {
      // A timeout can happen after the server accepted a request.
      // Keep the same key and fail closed; recovery must check current status.
      // A replay can identify a terminal booking, not a newly reserved slot.
      if (mounted && gen == _generation) {
        setState(() {
          _uncertain = true;
          _error = 'bookingRequestUncertain';
        });
      }
    } finally {
      if (mounted && gen == _generation) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.shop.name)),
    body: SafeArea(child: ListView(
      padding: const EdgeInsets.all(16),
      children: _sent ? [
        const Icon(Icons.mark_email_read_outlined, size: 48),
        Text(GarageUiText.get('bookingRequestSent'),
          key: const Key('booking_sent_notice')),
        OutlinedButton(key: const Key('booking_done'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(GarageUiText.get('bookingDone'))),
      ] : [
        Text(GarageUiText.get('bookingRequestDisclaimer'),
          key: const Key('booking_request_disclaimer')),
        const SizedBox(height: 8),
        Text(GarageUiText.format('bookingDeviceZoneHint', {
          'deviceZone': (_when ?? DateTime.now()).toLocal().timeZoneName,
          'workshopZone': widget.shop.timeZone,
        }),
          key: const Key('booking_time_zone_hint')),
        const SizedBox(height: 16),
        Form(key: _form, child: Column(children: [
          _field('booking_name', GarageUiText.get('bookingCustomerName'), _name),
          _field('booking_make', GarageUiText.get('bookingVehicleMake'), _make, limit: 80, min: 1),
          _field('booking_model', GarageUiText.get('bookingVehicleModel'), _model, limit: 80, min: 1),
          _field('booking_registration', GarageUiText.get('bookingRegistration'),
              _registration, limit: 30, min: 1, optional: true),
          DropdownButtonFormField<String>(
            key: const Key('booking_service'),
            value: _service,
            isExpanded: true,
            itemHeight: null,
            selectedItemBuilder: (context) => widget.shop.services.map((service) =>
              Align(alignment: AlignmentDirectional.centerStart,
                child: Text(bookingServiceLabel(service), maxLines: 1,
                  overflow: TextOverflow.ellipsis))).toList(),
            decoration: InputDecoration(border: const OutlineInputBorder(),
              labelText: GarageUiText.get('bookingService')),
            items: widget.shop.services.map((service) =>
              DropdownMenuItem(value: service, child: Text(bookingServiceLabel(service),
                maxLines: 2, overflow: TextOverflow.ellipsis))).toList(),
            onChanged: (value) => setState(() => _service = value),
            validator: (value) => value == null
                ? GarageUiText.get('bookingChooseService') : null,
          ),
          const SizedBox(height: 10),
          _field('booking_concern', GarageUiText.get('bookingConcern'),
              _concern, limit: 1000, min: 3, lines: 3),
        ])),
        OutlinedButton(
          key: const Key('booking_pick_time'), onPressed: _busy ? null : _pick,
          child: Text(_when == null
            ? GarageUiText.get('bookingPickTime')
            : bookingLocalTimeLabel(_when!))),
        if (_error != null) Text(GarageUiText.get(_error!), key: const Key('booking_request_error')),
        FilledButton(key: const Key('booking_send'),
          onPressed: _busy || _uncertain ? null : _send,
          child: Text(GarageUiText.get(_busy ? 'bookingSending' : 'bookingSubmitRequest'))),
      ],
    )),
  );
}
