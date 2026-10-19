import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_config.dart';
import '../core/formatters.dart';
import '../core/localization.dart';
import '../data/models.dart';
import '../garage/bridge_connections_screen.dart';
import 'smart_maintenance.dart';
import 'smart_maintenance_repository.dart';

/// QA-only Fleet screen. Requires a reviewed maintenance backend.
class SmartMaintenanceScreen extends StatefulWidget {
  const SmartMaintenanceScreen({
    required this.company, required this.vehicle, super.key,
  });
  final CompanyMembership company;
  final Vehicle vehicle;

  @override
  State<SmartMaintenanceScreen> createState() => _SmartMaintenanceScreenState();
}

class _SmartMaintenanceData {
  const _SmartMaintenanceData(this.plans, this.history, this.readings);
  final List<MaintenancePlan> plans;
  final List<MaintenanceHistory> history;
  final List<MaintenanceOdometerReading> readings;
}

class _SmartMaintenanceScreenState extends State<SmartMaintenanceScreen> {
  late final SmartMaintenanceRepository _repository;
  late Future<_SmartMaintenanceData> _future;
  late int _miles;
  bool _busy = false;

  bool get _pl => AppLocale.language.value == 'pl';
  String _t(String pl, String en) => _pl ? pl : en;
  MaintenanceUnit get _unit =>
      widget.company.currency.toUpperCase() == 'GBP'
          ? MaintenanceUnit.mi : MaintenanceUnit.km;

  String _name(MaintenanceKind kind) => switch (kind) {
    MaintenanceKind.oil => _t('Olej i filtr oleju', 'Oil and oil filter'),
    MaintenanceKind.brakes => _t('Kontrola hamulców', 'Brake inspection'),
    MaintenanceKind.timingBelt => _t('Rozrząd', 'Timing belt / chain'),
    MaintenanceKind.transmission => _t('Skrzynia biegów', 'Transmission'),
    MaintenanceKind.brakeFluid => _t('Płyn hamulcowy', 'Brake fluid'),
    MaintenanceKind.coolant => _t('Płyn chłodniczy', 'Coolant'),
    MaintenanceKind.filters => _t('Filtry', 'Filters'),
    MaintenanceKind.tyres => _t('Kontrola opon', 'Tyre inspection'),
    MaintenanceKind.roadTax => 'Road tax / VED',
    MaintenanceKind.other => _t('Inne', 'Other'),
  };

  String _attention(MaintenanceAttention value) => switch (value) {
    MaintenanceAttention.unscheduled => _t('Brak terminu', 'Unscheduled'),
    MaintenanceAttention.normal => _t('Zaplanowano', 'Scheduled'),
    MaintenanceAttention.upcoming => _t('Zbliża się termin', 'Due soon'),
    MaintenanceAttention.due => _t('Wymagany serwis', 'Due now'),
    MaintenanceAttention.overdue => _t('Po terminie', 'Overdue'),
  };

  @override
  void initState() {
    super.initState();
    _repository = SmartMaintenanceRepository(Supabase.instance.client);
    _miles = widget.vehicle.mileage;
    _refresh();
  }

  void _refresh() => _future = _load();

  Future<_SmartMaintenanceData> _load() async {
    final company = widget.company.companyId;
    final vehicle = widget.vehicle.id;
    final results = await Future.wait<Object>([
      _repository.plans(company, vehicle),
      _repository.history(company, vehicle),
      _repository.readings(company, vehicle),
    ]);
    return _SmartMaintenanceData(
      results[0] as List<MaintenancePlan>,
      results[1] as List<MaintenanceHistory>,
      results[2] as List<MaintenanceOdometerReading>,
    );
  }

  void _reload() { if (mounted) setState(_refresh); }

  void _error() {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
        _t('Zapis niepotwierdzony. Odśwież przed ponowieniem.',
           'Write not confirmed. Refresh before retrying.'))));
    }
  }

  Future<void> _configure([MaintenancePlan? original]) async {
    if (_busy) return;
    var kind = original?.kind ?? MaintenanceKind.oil;
    var unit = original?.unit ?? _unit;
    var lastDate = original?.lastServiceDate ?? DateTime.now();
    final distance = TextEditingController(
      text: original?.intervalDistance?.toString() ??
          (unit == MaintenanceUnit.km ? '10000' : '6214'));
    final months = TextEditingController(
      text: original?.intervalMonths?.toString() ?? '12');
    final last = TextEditingController(
      text: (original?.lastServiceMiles ?? _miles).toString());
    final note = TextEditingController(text: original?.notes ?? '');
    try {
      final yes = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, redraw) => AlertDialog(
            title: Text(_t('Harmonogram serwisu', 'Maintenance schedule')),
            content: SizedBox(width: 450, child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                DropdownButtonFormField<MaintenanceKind>(
                  initialValue: kind,
                  decoration: InputDecoration(labelText: _t('Czynność', 'Task')),
                  items: [
                    for (final value in MaintenanceKind.values)
                      DropdownMenuItem(value: value, child: Text(_name(value))),
                  ],
                  onChanged: original != null ? null : (value) {
                    if (value != null) redraw(() {
                      kind = value;
                      if (value != MaintenanceKind.oil) {
                        distance.clear();
                        months.clear();
                      }
                    });
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<MaintenanceUnit>(
                  initialValue: unit,
                  decoration: InputDecoration(labelText: _t('Jednostka', 'Unit')),
                  items: const [
                    DropdownMenuItem(value: MaintenanceUnit.km, child: Text('km')),
                    DropdownMenuItem(value: MaintenanceUnit.mi, child: Text('mi')),
                  ],
                  onChanged: (next) {
                    if (next == null || next == unit) return;
                    redraw(() {
                      final oldDistance = int.tryParse(distance.text);
                      if (oldDistance != null && oldDistance >= 0) {
                        distance.text = (next == MaintenanceUnit.km
                            ? fromMiles(toMiles(oldDistance, unit), next)
                            : toMiles(oldDistance, unit)).toString();
                      }
                      unit = next;
                    });
                  },
                ),
                TextField(controller: distance,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText:
                    _t('Interwał przebiegu (opcjonalnie)',
                       'Distance interval (optional)'))),
                TextField(controller: months,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText:
                    _t('Interwał w miesiącach (opcjonalnie)',
                       'Interval in months (optional)'))),
                TextField(controller: last,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText:
                    _t('Ostatni serwis — przebieg w milach',
                       'Last service odometer (miles)'))),
                ListTile(
                  title: Text(_t('Data ostatniego serwisu', 'Last service date')),
                  subtitle: Text(formatDate(lastDate)),
                  trailing: const Icon(Icons.calendar_month_outlined),
                  onTap: () async {
                    final date = await showDatePicker(context: ctx,
                      initialDate: lastDate, firstDate: DateTime(2000),
                      lastDate: DateTime.now());
                    if (date != null) redraw(() => lastDate = date);
                  },
                ),
                TextField(controller: note, maxLength: 1000, maxLines: 2,
                  decoration: InputDecoration(labelText:
                    _t('Uwagi producenta / warsztatu',
                       'Manufacturer / garage notes'))),
                Text(_t(
                  '10 000 km jest edytowalną propozycją dla oleju, nie '
                  'zaleceniem dla wszystkich pojazdów.',
                  '10,000 km is an editable oil-service suggestion, '
                  'not a universal manufacturer interval.')),
              ]),
            )),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: Text(_t('Anuluj', 'Cancel'))),
              FilledButton(onPressed: () => Navigator.pop(ctx, true),
                child: Text(_t('Zapisz', 'Save'))),
            ],
          ),
        ),
      );
      if (yes != true || !mounted) return;
      final n = distance.text.trim().isEmpty ? null : int.tryParse(distance.text);
      final m = months.text.trim().isEmpty ? null : int.tryParse(months.text);
      final lastMiles = int.tryParse(last.text);
      if ((distance.text.trim().isNotEmpty && n == null) ||
          (months.text.trim().isNotEmpty && m == null) ||
          (n == null && m == null) ||
          (n != null && (n < 1 || n > 500000)) ||
          (m != null && (m < 1 || m > 240)) ||
          lastMiles == null || lastMiles < 0 || lastMiles > _miles) {
        _error(); return;
      }
      setState(() => _busy = true);
      try {
        await _repository.setPlan(
          companyId: widget.company.companyId,
          vehicleId: widget.vehicle.id,
          kind: kind, unit: unit,
          intervalDistance: n, intervalMonths: m,
          lastServiceMiles: lastMiles, lastServiceDate: lastDate,
          notes: note.text.trim(),
        );
        _reload();
      } catch (_) { _error(); }
      finally { if (mounted) setState(() => _busy = false); }
    } finally {
      distance.dispose();
      months.dispose();
      last.dispose();
      note.dispose();
    }
  }

  Future<void> _complete(MaintenancePlan plan) async {
    if (_busy) return;
    final miles = TextEditingController(text: _miles.toString());
    final notes = TextEditingController();
    var date = DateTime.now();
    try {
      final yes = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(builder: (ctx, redraw) => AlertDialog(
          title: Text(_t('Serwis zakończony', 'Complete service')),
          content: SizedBox(width: 420, child: Column(
            mainAxisSize: MainAxisSize.min, children: [
              Text(_name(plan.kind)),
              TextField(controller: miles, keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: _t(
                  'Przebieg w milach', 'Odometer in miles'))),
              ListTile(
                title: Text(_t('Data wykonania', 'Completion date')),
                subtitle: Text(formatDate(date)),
                onTap: () async {
                  final selected = await showDatePicker(context: ctx,
                    firstDate: plan.lastServiceDate,
                    lastDate: DateTime.now(), initialDate: date);
                  if (selected != null) redraw(() => date = selected);
                },
              ),
              TextField(controller: notes, maxLength: 1000,
                decoration: InputDecoration(labelText:
                  _t('Opis wykonanych prac', 'Service note'))),
              Text(_t('Historia i kolejny termin zostaną zapisane. '
                  'Nie nastąpi automatyczna płatność ani rezerwacja.',
                  'History and the next due date will be saved. '
                  'No automatic payment or booking.')),
            ],
          )),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: Text(_t('Anuluj', 'Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true),
              child: Text(_t('Potwierdź', 'Confirm'))),
          ],
        )),
      );
      if (yes != true || !mounted) return;
      final value = int.tryParse(miles.text.trim());
      if (value == null || value < plan.lastServiceMiles || value > _miles ||
          date.isBefore(plan.lastServiceDate)) { _error(); return; }
      setState(() => _busy = true);
      try {
        await _repository.complete(
          companyId: widget.company.companyId, planId: plan.id,
          completedMiles: value, completedDate: date,
          note: notes.text.trim(),
        );
        _reload();
      } catch (_) { _error(); }
      finally { if (mounted) setState(() => _busy = false); }
    } finally { miles.dispose(); notes.dispose(); }
  }

  Future<void> _odometer() async {
    if (_busy) return;
    final miles = TextEditingController(text: _miles.toString());
    try {
      final yes = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(_t('Zapis przebiegu', 'Record odometer')),
          content: TextField(controller: miles, keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: _t('Mile', 'Miles'))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: Text(_t('Anuluj', 'Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true),
              child: Text(_t('Zapisz', 'Save'))),
          ],
        ),
      );
      if (yes != true || !mounted) return;
      final value = int.tryParse(miles.text.trim());
      if (value == null || value < _miles) { _error(); return; }
      setState(() => _busy = true);
      try {
        await _repository.recordOdometer(
          companyId: widget.company.companyId,
          vehicleId: widget.vehicle.id,
          miles: value, date: DateTime.now(),
        );
        if (mounted) setState(() => _miles = value);
        _reload();
      } catch (_) { _error(); }
      finally { if (mounted) setState(() => _busy = false); }
    } finally { miles.dispose(); }
  }

  void _garages() {
    if (!AppConfig.ecosystemQaEnabled) return;
    Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => GarageBridgeConnectionsScreen.forClient(
        client: Supabase.instance.client,
        scopeId: widget.company.companyId, fleet: true)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Smart Maintenance')),
    body: FutureBuilder<_SmartMaintenanceData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_t('Harmonogram niedostępny na tym backendzie.',
                'Maintenance is unavailable on this backend.')),
            TextButton(onPressed: _reload, child: Text(_t('Ponów', 'Retry'))),
          ]));
        }
        final data = snapshot.data!;
        return RefreshIndicator(
          onRefresh: () async { _reload(); await _future; },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              Text(widget.vehicle.registration + ' • ' +
                formatMileage(_miles) + ' mi',
                style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                FilledButton.icon(
                  onPressed: _busy ? null : () => _configure(),
                  icon: const Icon(Icons.add),
                  label: Text(_t('Dodaj czynność', 'Add task'))),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _odometer,
                  icon: const Icon(Icons.speed),
                  label: Text(_t('Nowy przebieg', 'Record odometer'))),
              ]),
              const SizedBox(height: 12),
              for (final plan in data.plans)
                Card(child: Padding(padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_name(plan.kind),
                        style: Theme.of(context).textTheme.titleMedium),
                      Text(_attention(plan.attention(_miles, DateTime.now()))),
                      if (plan.nextDueMiles != null)
                        Text(_t('Następny przebieg: ', 'Next due: ') +
                          formatMileage(fromMiles(plan.nextDueMiles!, plan.unit)) +
                          ' ' + plan.unit.name),
                      if (plan.nextDueDate != null)
                        Text(_t('Termin: ', 'Date: ') +
                          formatDate(plan.nextDueDate)),
                      if (data.readings.length >= 2 && plan.nextDueMiles != null)
                        Builder(builder: (_) {
                          final predicted = estimateDueDate(
                            remainingMiles: plan.nextDueMiles! - _miles,
                            older: data.readings[1],
                            newer: data.readings.first,
                          );
                          return predicted == null ? const SizedBox.shrink()
                            : Text(_t('Prognoza: ', 'Estimate: ') +
                                formatDate(predicted));
                        }),
                      Wrap(spacing: 8, children: [
                        TextButton(onPressed: _busy ? null :
                          () => _configure(plan),
                          child: Text(_t('Edytuj', 'Edit'))),
                        FilledButton.tonal(onPressed: _busy ? null :
                          () => _complete(plan),
                          child: Text(_t('Wykonano', 'Complete'))),
                      ]),
                    ],
                  ),
                )),
              if (data.plans.isEmpty)
                Text(_t('Dodaj harmonogram oleju lub innej czynności.',
                  'Add an oil or other maintenance schedule.')),
              const SizedBox(height: 20),
              Text(_t('Historia serwisu', 'Service history'),
                style: Theme.of(context).textTheme.titleMedium),
              for (final event in data.history)
                ListTile(
                  leading: const Icon(Icons.check_circle_outline),
                  title: Text(_name(event.kind)),
                  subtitle: Text(formatDate(event.completedDate) + ' • ' +
                    formatMileage(event.completedMiles) + ' mi • ' + event.note),
                ),
              if (AppConfig.ecosystemQaEnabled)
                Card(child: ListTile(
                  title: Text(_t('Flotaryx Garage', 'Flotaryx Garage')),
                  subtitle: Text(_t(
                    'Przejdź do połączonych warsztatów. Zgłoszenie wymaga '
                    'osobnej zgody i istniejącej usterki.',
                    'View connected workshops. Sending a request requires '
                    'separate consent and an existing defect.')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _garages,
                )),
              Text(_t(
                'Harmonogram jest wskazówką, nie uniwersalnym zaleceniem. '
                'Brak automatycznego wysyłania e-maili.',
                'Intervals are not universal manufacturer guidance. '
                'No automatic emails are sent.')),
            ],
          ),
        );
      },
    ),
  );
}
