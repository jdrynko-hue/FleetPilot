import 'package:flutter/material.dart';

import '../core/localization.dart';
import 'consumer_booking_repository.dart';

typedef BookingSearch = Future<List<GarageBookingWorkshop>> Function({String? city});
typedef BookingSubmit = Future<String> Function({
  required String workspaceId, required String customerName,
  required String vehicleMake, required String vehicleModel,
  required String service, required String concern,
  required DateTime desiredStart, String? registration,
});
typedef BookingTimePicker = Future<DateTime?> Function(BuildContext context);

/// Staging only. No production Fleet navigation or guaranteed availability.
class GarageBookingSearchScreen extends StatefulWidget {
  const GarageBookingSearchScreen({
    required this.search, required this.submit,
    this.pickTime = pickBookingTime, super.key,
  });

  factory GarageBookingSearchScreen.forRepository(
    GarageBookingRepository repository, {Key? key}) =>
      GarageBookingSearchScreen(
        key: key, search: repository.findWorkshops,
        submit: repository.request);

  final BookingSearch search;
  final BookingSubmit submit;
  final BookingTimePicker pickTime;

  @override
  State<GarageBookingSearchScreen> createState() => _GarageBookingSearchState();
}

class _GarageBookingSearchState extends State<GarageBookingSearchScreen> {
  final _city = TextEditingController();
  List<GarageBookingWorkshop> _shops = const [];
  bool _busy = false;
  String? _error;
  int _generation = 0;

  bool get _pl => AppLocale.language.value == 'pl';
  String tr(String pl, String en) => _pl ? pl : en;

  @override
  void didUpdateWidget(covariant GarageBookingSearchScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.search != widget.search ||
        oldWidget.submit != widget.submit ||
        oldWidget.pickTime != widget.pickTime) {
      // Repository callbacks define the authenticated directory scope.
      // Invalidate old in-flight results and never show another scope's shops.
      _generation++;
      _shops = const [];
      _error = null;
      _busy = false;
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
      setState(() => _error = tr('Wpisz co najmniej 2 znaki.',
          'Enter at least two characters.'));
      return;
    }
    final gen = ++_generation;
    final search = widget.search;
    setState(() { _busy = true; _shops = const []; _error = null; });
    try {
      final result = await search(city: city.isEmpty ? null : city);
      if (!mounted || gen != _generation) return;
      setState(() {
        _shops = List.unmodifiable(result);
        if (result.isEmpty) {
          _error = tr('Brak zgłoszonych warsztatów.',
              'No workshops accepting requests found.');
        }
      });
    } catch (_) {
      if (!mounted || gen != _generation) return;
      setState(() {
        _shops = const [];
        _error = tr('Nie można pobrać katalogu. Spróbuj ponownie.',
            'Could not load workshops. Retry.');
      });
    } finally {
      if (mounted && gen == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _open(GarageBookingWorkshop shop) async {
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => GarageBookingRequestScreen(
        shop: shop, submit: widget.submit, pickTime: widget.pickTime),
    ));
    if (mounted) await _search();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr('Znajdź mechanika', 'Find a mechanic'))),
    body: SafeArea(child: ListView(padding: const EdgeInsets.all(16),
      children: [
        Text(tr('Wybierz warsztat i poproś o termin. Godzinę musi '
                'potwierdzić mechanik.',
                'Request a preferred time. The workshop must confirm it.'),
            key: const Key('booking_not_guaranteed')),
        const SizedBox(height: 16),
        TextField(key: const Key('booking_search_city'),
          controller: _city, maxLength: 80,
          onSubmitted: (_) => _search(),
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            labelText: tr('Miasto (opcjonalnie)', 'City (optional)'))),
        FilledButton(key: const Key('booking_search_submit'),
          onPressed: _busy ? null : _search,
          child: Text(tr('Szukaj warsztatów', 'Search workshops'))),
        if (_busy) const Center(child: CircularProgressIndicator()),
        if (_error != null) Text(_error!,
          key: const Key('booking_search_error')),
        for (final shop in _shops) Card(
          key: Key('booking_shop_${shop.workspaceId}'),
          child: Padding(padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(shop.name, style: Theme.of(context).textTheme.titleMedium),
                Text('${shop.city}, ${shop.country}'),
                Text(shop.services.join(', ')),
                Text(tr('Strefa czasowa: ${shop.timeZone}',
                    'Workshop time zone: ${shop.timeZone}')),
                OutlinedButton(key: Key('booking_open_${shop.workspaceId}'),
                  onPressed: _busy ? null : () => _open(shop),
                  child: Text(tr('Poproś o termin', 'Request a time'))),
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
  return DateTime(day.year, day.month, day.day, time.hour, time.minute);
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

  bool get _pl => AppLocale.language.value == 'pl';
  String tr(String pl, String en) => _pl ? pl : en;

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
          ? null : tr('Uzupełnij prawidłowo pole.', 'Enter a valid value.');
      });

  Future<void> _pick() async {
    if (_busy || _sent) return;
    final gen = _generation;
    final pickTime = widget.pickTime;
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
      setState(() => _error = tr('Wybierz termin w ciągu 90 dni.',
          'Select a time within 90 days.'));
      return;
    }
    final gen = ++_generation;
    final submit = widget.submit;
    final workspaceId = widget.shop.workspaceId;
    setState(() { _busy = true; _error = null; });
    try {
      await submit(
        workspaceId: workspaceId,
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
      // Without an idempotency key, retrying could create a duplicate.
      if (mounted && gen == _generation) {
        setState(() {
          _uncertain = true;
          _error = tr(
            'Nie można potwierdzić wysłania. Sprawdź „Moje terminy” '
            'przed ponownym wysłaniem zgłoszenia. '
            'Wróć do listy warsztatów.',
            'Request outcome is uncertain. Check My appointments '
            'before submitting another request. '
            'Return to the workshop list.',
          );
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
        Text(tr('Prośba wysłana — termin NIE jest potwierdzony.',
            'Request sent — your appointment is NOT confirmed.'),
          key: const Key('booking_sent_notice')),
        OutlinedButton(key: const Key('booking_done'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr('Gotowe', 'Done'))),
      ] : [
        Text(tr('Zgłoszenie jest bezpłatne. Warsztat potwierdzi termin '
            'i ewentualną wycenę osobno.',
            'The request is free. The workshop will confirm the time '
            'and any estimate separately.'),
          key: const Key('booking_request_disclaimer')),
        const SizedBox(height: 8),
        Text(tr('Wpisz czas według strefy urządzenia '
            '(${DateTime.now().timeZoneName}); warsztat: ${widget.shop.timeZone}.',
            'Enter a time in your device zone '
            '(${DateTime.now().timeZoneName}); workshop: ${widget.shop.timeZone}.')),
        const SizedBox(height: 16),
        Form(key: _form, child: Column(children: [
          _field('booking_name', tr('Imię i nazwisko', 'Full name'), _name),
          _field('booking_make', tr('Marka', 'Make'), _make, limit: 80, min: 1),
          _field('booking_model', tr('Model', 'Model'), _model, limit: 80, min: 1),
          _field('booking_registration', tr('Rejestracja (opcjonalnie)', 'Registration (optional)'),
              _registration, limit: 30, min: 1, optional: true),
          DropdownButtonFormField<String>(
            key: const Key('booking_service'),
            value: _service,
            decoration: InputDecoration(border: const OutlineInputBorder(),
              labelText: tr('Usługa', 'Service')),
            items: widget.shop.services.map((service) =>
              DropdownMenuItem(value: service, child: Text(service))).toList(),
            onChanged: (value) => setState(() => _service = value),
            validator: (value) => value == null
                ? tr('Wybierz usługę.', 'Choose a service.') : null,
          ),
          const SizedBox(height: 10),
          _field('booking_concern', tr('Opisz problem', 'Describe the issue'),
              _concern, limit: 1000, min: 3, lines: 3),
        ])),
        OutlinedButton(
          key: const Key('booking_pick_time'), onPressed: _busy ? null : _pick,
          child: Text(_when == null
            ? tr('Wybierz datę i godzinę', 'Choose date and time')
            : _when!.toLocal().toString().substring(0, 16))),
        if (_error != null) Text(_error!, key: const Key('booking_request_error')),
        FilledButton(key: const Key('booking_send'),
          onPressed: _busy || _uncertain ? null : _send,
          child: Text(_busy ? tr('Wysyłanie…', 'Sending…') :
            tr('Wyślij prośbę (bez rezerwacji)', 'Send request (not booked)'))),
      ],
    )),
  );
}
