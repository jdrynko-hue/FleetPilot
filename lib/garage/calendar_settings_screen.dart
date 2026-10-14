import 'package:flutter/material.dart';

import '../core/localization.dart';
import 'resource_calendar_repository.dart';

/// Staging-only owner configuration of weekly hours and intake bays.
/// Existing confirmed visits are never implicitly cancelled on hour changes.
class GarageCalendarSettingsScreen extends StatefulWidget {
  const GarageCalendarSettingsScreen({
    required this.loadHours,
    required this.loadResources,
    required this.setHours,
    required this.addResource,
    required this.setResourceActive,
    this.loadMechanics,
    this.assignMechanic,
    super.key,
  });

  factory GarageCalendarSettingsScreen.forRepository({
    required GarageResourceCalendarRepository repository,
    required String workspaceId,
    Key? key,
  }) => GarageCalendarSettingsScreen(
    key: key,
    loadHours: () => repository.openingHours(workspaceId),
    loadResources: () => repository.resources(workspaceId),
    setHours: (day, opens, closes, enabled) => repository.setHours(
      shopId: workspaceId, weekday: day, opensAt: opens,
      closesAt: closes, enabled: enabled),
    addResource: (name) => repository.addResource(
      shopId: workspaceId, name: name),
    setResourceActive: (id, active) => repository.setResourceActive(
      shopId: workspaceId, resourceId: id, active: active),
    loadMechanics: () => repository.mechanics(workspaceId),
    assignMechanic: (id, mechanic) => repository.assignResourceMechanic(
      shopId: workspaceId, resourceId: id, mechanicUserId: mechanic),
  );

  final Future<List<GarageOpeningHours>> Function() loadHours;
  final Future<List<GarageCalendarResource>> Function() loadResources;
  final Future<bool> Function(int day, String opensAt, String closesAt,
      bool enabled) setHours;
  final Future<String> Function(String name) addResource;
  final Future<bool> Function(String id, bool active) setResourceActive;
  /// Optional during staged rollout; only Garage owner can view staff emails.
  final Future<List<GarageRosterMechanic>> Function()? loadMechanics;
  final Future<bool> Function(String resourceId, String? mechanicUserId)?
      assignMechanic;

  @override
  State<GarageCalendarSettingsScreen> createState() =>
      _GarageCalendarSettingsState();
}

class _GarageCalendarSettingsState extends State<GarageCalendarSettingsScreen> {
  List<GarageOpeningHours> _hours = const [];
  List<GarageCalendarResource> _resources = const [];
  List<GarageRosterMechanic> _mechanics = const [];
  bool _busy = true;
  String? _notice;
  int _version = 0;

  bool get _pl => AppLocale.language.value == 'pl';
  String tr(String pl,String en) => _pl ? pl : en;
  static const _daysEn=['Monday','Tuesday','Wednesday','Thursday','Friday',
    'Saturday','Sunday'];
  static const _daysPl=['Poniedziałek','Wtorek','Środa','Czwartek','Piątek',
    'Sobota','Niedziela'];

  @override
  void initState() { super.initState(); _reload(); }
  @override
  void dispose() { _version++; super.dispose(); }

  Future<void> _reload() async {
    if (!mounted) return;
    final version = ++_version;
    setState(() {
      _busy = true; _notice = null;
      _hours = const []; _resources = const []; _mechanics = const [];
    });
    try {
      final hours = await widget.loadHours();
      final resources = await widget.loadResources();
      final mechanics = widget.loadMechanics == null
          ? <GarageRosterMechanic>[]
          : await widget.loadMechanics!();
      if (!mounted || version != _version) return;
      setState(() {
        _hours = List.unmodifiable(hours);
        _resources = List.unmodifiable(resources);
        _mechanics = List.unmodifiable(mechanics);
      });
    } catch (_) {
      if (mounted && version == _version) {
        setState(() => _notice = tr('Nie udało się odczytać ustawień.',
          'Could not load workshop settings or permissions.'));
      }
    } finally {
      if (mounted && version == _version) setState(() => _busy = false);
    }
  }

  static TimeOfDay _parse(String text) {
    final pieces = text.split(':');
    return TimeOfDay(hour:int.parse(pieces[0]),minute:int.parse(pieces[1]));
  }

  static String _format(TimeOfDay time) =>
    time.hour.toString().padLeft(2,'0') + ':' +
    time.minute.toString().padLeft(2,'0') + ':00';

  Future<void> _changeHours(int weekday) async {
    if (_busy) return;
    final existing = _hours.where((h)=>h.isoWeekday==weekday).firstOrNull;
    final enable = await showDialog<bool?>(context:context,
      builder:(context)=>AlertDialog(
        title:Text(tr('Godziny otwarcia','Opening hours')),
        content:Text(tr(
          'Wybierz „Ustaw” dla godzin pracy lub „Zamknij” dla dnia wolnego. '
          'Istniejące potwierdzone wizyty wymagają ręcznego rozwiązania.',
          'Set working hours or close the day. Existing confirmed appointments '
          'must be resolved separately.')),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(context),
            child:Text(tr('Wróć','Back'))),
          OutlinedButton(
            key:const Key('garage_hours_close_day'),
            onPressed:()=>Navigator.pop(context,false),
            child:Text(tr('Zamknij dzień','Close day'))),
          FilledButton(
            key:const Key('garage_hours_edit_day'),
            onPressed:()=>Navigator.pop(context,true),
            child:Text(tr('Ustaw godziny','Set hours'))),
        ]));
    if (!mounted || enable == null) return;
    var opens = existing?.opensAt ?? '08:00:00';
    var closes = existing?.closesAt ?? '17:00:00';
    if (enable) {
      final first = await showTimePicker(context:context,
        initialTime:_parse(opens));
      if (first == null || !mounted) return;
      final last = await showTimePicker(context:context,
        initialTime:_parse(closes));
      if (last == null || !mounted) return;
      opens = _format(first);
      closes = _format(last);
      if (opens.compareTo(closes)>=0) {
        setState(()=>_notice=tr('Zamknięcie musi być później niż otwarcie.',
          'Closing time must be later than opening time.'));
        return;
      }
    }
    await _mutate(() => widget.setHours(weekday,opens,closes,enable));
  }

  Future<void> _newResource() async {
    if (_busy) return;
    var enteredName = '';
    final name = await showDialog<String>(context:context,
      builder:(context) {
        return AlertDialog(
          title:Text(tr('Dodaj stanowisko','Add workshop bay')),
          content:TextField(
            key:const Key('garage_resource_name'),
            onChanged:(value)=>enteredName=value,maxLength:70,
            decoration:InputDecoration(labelText:tr('Nazwa stanowiska','Bay name')),
          ),
          actions:[
            TextButton(onPressed:()=>Navigator.pop(context),
              child:Text(tr('Wróć','Back'))),
            FilledButton(
              key:const Key('garage_resource_save'),
              onPressed:()=>Navigator.pop(context,enteredName.trim()),
              child:Text(tr('Dodaj','Add'))),
          ],
        );
      });
    if (!mounted || name == null) return;
    if (name.length < 2 || name.length > 70) {
      setState(()=>_notice=tr('Podaj nazwę od 2 do 70 znaków.',
        'Enter a bay name of 2 to 70 characters.'));
      return;
    }
    await _mutate(() async { await widget.addResource(name); return true; });
  }

  Future<void> _toggle(GarageCalendarResource resource) async {
    if (_busy) return;
    final allow = await showDialog<bool>(context:context,
      builder:(context)=>AlertDialog(
        title:Text(tr('Zmień dostępność stanowiska','Update bay status')),
        content:Text(resource.active
          ? tr('Wyłączenie będzie zablokowane, jeśli istnieją przyszłe '
               'potwierdzone wizyty.','Deactivation is blocked while future '
               'confirmed appointments exist.')
          : tr('Aktywować stanowisko?','Activate this bay?')),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(context,false),
            child:Text(tr('Wróć','Back'))),
          FilledButton(
            key:const Key('garage_resource_confirm_toggle'),
            onPressed:()=>Navigator.pop(context,true),
            child:Text(tr('Potwierdź','Confirm'))),
        ]));
    if (!mounted || allow != true) return;
    await _mutate(()=>widget.setResourceActive(resource.id,!resource.active));
  }

  /// Staff list stays restricted to owners; confirmation is rechecked by SQL.
  Future<void> _chooseMechanic(GarageCalendarResource resource) async {
    if (_busy || widget.assignMechanic == null) return;
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Mechanik stanowiska', 'Assign bay mechanic')),
        content: SizedBox(
          width: double.maxFinite,
          height: 320,
          child: ListView(children: [
            Text(tr('Nie można zmienić mechanika, gdy stanowisko ma '
                'trwającą lub przyszłą potwierdzoną wizytę.',
                'Reassignment is blocked while a confirmed booking '
                'is active or scheduled.')),
            ListTile(
              key: const Key('garage_mechanic_unassign'),
              title: Text(tr('Bez przypisania', 'Unassigned')),
              selected: resource.mechanicUserId == null,
              onTap: () => Navigator.pop(context, '__unassigned__'),
            ),
            for (final mechanic in _mechanics)
              ListTile(
                key: Key('garage_mechanic_pick_' + mechanic.userId),
                title: Text(mechanic.email),
                selected: mechanic.userId == resource.mechanicUserId,
                onTap: () => Navigator.pop(context, mechanic.userId),
              ),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('Wróć', 'Back')),
          ),
        ],
      ),
    );
    if (!mounted || selected == null || _busy) return;
    final mechanicId = selected == '__unassigned__' ? null : selected;
    if (resource.mechanicUserId == mechanicId) return;
    await _mutate(() => widget.assignMechanic!(resource.id, mechanicId));
  }

  Future<void> _mutate(Future<bool> Function() write) async {
    if (_busy) return;
    setState(() {
      _busy=true; _notice=null; _resources=const [];
      _hours=const []; _mechanics=const [];
    });
    var failed=false;
    try {
      if (!await write()) throw const FormatException('Not confirmed');
    } catch (_) { failed=true; }
    if (mounted) {
      await _reload();
      if (mounted && failed) setState(() => _notice=tr(
        'Zmiana nie została potwierdzona. Sprawdź grafik i spróbuj ponownie.',
        'Change not confirmed. Check your calendar and retry.'));
    }
  }

  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text(tr('Ustawienia kalendarza','Calendar settings')),
      actions:[IconButton(key:const Key('garage_settings_refresh'),
        onPressed:_busy?null:_reload,icon:const Icon(Icons.refresh))]),
    body:SafeArea(child:_busy
      ? const Center(child:CircularProgressIndicator())
      : ListView(padding:const EdgeInsets.all(16),children:[
        Text(tr('Godziny otwarcia', 'Weekly opening hours'),
          style:Theme.of(context).textTheme.titleLarge),
        Text(tr('Zmiany godzin nie usuwają już potwierdzonych wizyt.',
          'Changes to hours never silently cancel existing bookings.')),
        if(_notice!=null)Text(_notice!,key:const Key('garage_settings_notice')),
        for(var weekday=1;weekday<=7;weekday++)
          ListTile(
            key:Key('garage_settings_weekday_' + weekday.toString()),
            title:Text(_pl?_daysPl[weekday-1]:_daysEn[weekday-1]),
            subtitle:Text(
              _hours.any((h)=>h.isoWeekday==weekday)
                ? _hours.firstWhere((h)=>h.isoWeekday==weekday).opensAt
                  + ' – ' +
                  _hours.firstWhere((h)=>h.isoWeekday==weekday).closesAt
                : tr('Zamknięte','Closed')),
            trailing:const Icon(Icons.edit_calendar),
            onTap:()=>_changeHours(weekday)),
        const SizedBox(height:16),
        Text(tr('Stanowiska', 'Workshop bays'),
          style:Theme.of(context).textTheme.titleLarge),
        for(final resource in _resources)
          ListTile(key:Key('garage_settings_bay_' + resource.id),
            title:Text(resource.name),
            subtitle:Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(resource.active
                  ? tr('Aktywne','Active') : tr('Nieaktywne','Inactive')),
                if (widget.loadMechanics != null)
                  Text(resource.mechanicUserId == null
                    ? tr('Mechanik: brak', 'Mechanic: unassigned')
                    : (_mechanics.where(
                        (m) => m.userId == resource.mechanicUserId)
                        .firstOrNull?.email ??
                        tr('Mechanik nie jest już w zespole',
                           'Mechanic is no longer on staff'))),
              ],
            ),
            trailing:Row(mainAxisSize:MainAxisSize.min,children:[
              if (widget.loadMechanics != null &&
                  widget.assignMechanic != null)
                IconButton(
                  key:Key('garage_settings_assign_' + resource.id),
                  tooltip:tr('Przypisz mechanika','Assign mechanic'),
                  onPressed:()=>_chooseMechanic(resource),
                  icon:const Icon(Icons.person_outline)),
              IconButton(
                key:Key('garage_settings_toggle_' + resource.id),
                onPressed:()=>_toggle(resource),
                icon:Icon(resource.active ? Icons.pause_circle_outline
                  : Icons.play_circle_outline)),
            ])),
        FilledButton.icon(key:const Key('garage_settings_add_bay'),
          onPressed:_newResource,icon:const Icon(Icons.add),
          label:Text(tr('Dodaj stanowisko', 'Add bay'))),
        const SizedBox(height:16),
        Text(tr('Przypisanie mechaników do stanowisk wymaga odpowiednich '
            'uprawnień i dostępnej listy personelu.',
            'Assigning mechanics to bays requires an authorized staff roster.'),
          style:Theme.of(context).textTheme.bodySmall),
      ])),
  );
}
