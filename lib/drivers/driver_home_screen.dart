import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../checks/check_logic.dart';
import '../core/localization.dart';
import '../data/models.dart';

String _phrase(String en, String pl) =>
    AppLocale.language.value == 'pl' ? pl : en;

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({required this.company, super.key});
  final CompanyMembership company;

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  final _client = Supabase.instance.client;
  late Future<_DriverData> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _future = _fetch();

  List<Map<String, dynamic>> _records(dynamic value) => value is List
      ? value.map((entry) => Map<String, dynamic>.from(entry as Map)).toList()
      : <Map<String, dynamic>>[];

  Future<_DriverData> _fetch() async {
    final companyId = widget.company.companyId;
    final access = await _client.rpc(
      'fleetpilot_driver_feature_enabled',
      params: {'_company_id': companyId},
    );
    final driver = _records(
      await _client.rpc(
        'fleetpilot_my_driver_profile',
        params: {'_company_id': companyId},
      ),
    );
    final van = _records(
      await _client.rpc(
        'fleetpilot_my_vehicle',
        params: {'_company_id': companyId},
      ),
    );
    final issues = _records(
      await _client.rpc(
        'fleetpilot_my_driver_issues',
        params: {'_company_id': companyId},
      ),
    );
    final changes = _records(
      await _client.rpc(
        'fleetpilot_list_vehicle_change_requests',
        params: {'_company_id': companyId},
      ),
    );
    final options = _records(
      await _client.rpc(
        'fleetpilot_vehicle_change_options',
        params: {'_company_id': companyId},
      ),
    );
    return _DriverData(
      enabled: access == true,
      profile: driver.isEmpty ? null : driver.first,
      vehicle: van.isEmpty ? null : van.first,
      issues: issues,
      changes: changes,
      options: options,
    );
  }

  void _message(String value) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(value)));
    }
  }

  Future<void> _reportIssue(_DriverData data) async {
    if (data.vehicle == null || _busy) return;
    final title = TextEditingController();
    final description = TextEditingController();
    final mileage = TextEditingController();
    var priority = 'medium';
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: Text(_phrase('Report a defect', 'Zgłoś usterkę')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${data.vehicle!['registration']}'),
                const SizedBox(height: 12),
                TextField(
                  controller: title,
                  maxLength: 180,
                  decoration: InputDecoration(
                    labelText: _phrase('Problem title', 'Nazwa usterki'),
                  ),
                ),
                TextField(
                  controller: description,
                  maxLines: 3,
                  maxLength: 2000,
                  decoration: InputDecoration(
                    labelText: _phrase('Description', 'Opis'),
                  ),
                ),
                TextField(
                  controller: mileage,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: _phrase(
                      'Odometer (optional)',
                      'Przebieg (opcjonalnie)',
                    ),
                  ),
                ),
                DropdownButtonFormField<String>(
                  initialValue: priority,
                  decoration: InputDecoration(
                    labelText: _phrase('Priority', 'Priorytet'),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'low', child: Text('Low')),
                    DropdownMenuItem(value: 'medium', child: Text('Medium')),
                    DropdownMenuItem(value: 'high', child: Text('High')),
                    DropdownMenuItem(
                      value: 'critical',
                      child: Text('Critical'),
                    ),
                  ],
                  onChanged: (value) =>
                      refresh(() => priority = value ?? 'medium'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(_phrase('Cancel', 'Anuluj')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, {
                'title': title.text.trim(),
                'description': description.text.trim(),
                'priority': priority,
                'mileage': mileage.text.trim(),
              }),
              child: Text(_phrase('Send', 'Wyślij')),
            ),
          ],
        ),
      ),
    );
    title.dispose();
    description.dispose();
    mileage.dispose();
    if (result == null || !mounted) return;
    if (result['title']!.length < 3) {
      _message(
        _phrase(
          'Give the problem a title (at least 3 characters).',
          'Wpisz nazwę usterki (minimum 3 znaki).',
        ),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await _client.rpc(
        'fleetpilot_report_driver_issue',
        params: {
          '_company_id': widget.company.companyId,
          '_title': result['title'],
          '_description': result['description'],
          '_priority': result['priority'],
          '_mileage': result['mileage']!.isEmpty
              ? null
              : int.parse(result['mileage']!),
        },
      );
      if (mounted) setState(_reload);
      _message(
        _phrase(
          'Defect reported to your manager.',
          'Usterka została zgłoszona managerowi.',
        ),
      );
    } catch (error) {
      _message(
        '${_phrase('Unable to report defect', 'Nie udało się zgłosić usterki')}: $error',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _requestChange(_DriverData data) async {
    if (_busy) return;
    final available = data.options
        .where(
          (row) =>
              row['is_available'] == true && row['id'] != data.vehicle?['id'],
        )
        .toList();
    if (available.isEmpty) {
      _message(
        _phrase(
          'No unassigned vehicles available. Ask your manager.',
          'Brak wolnych vanów. Skontaktuj się z managerem.',
        ),
      );
      return;
    }
    String? target;
    final reason = TextEditingController();
    final answer = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: Text(_phrase('Request another van', 'Poproś o zmianę vana')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: target,
                  decoration: InputDecoration(
                    labelText: _phrase('New van', 'Nowy van'),
                  ),
                  items: available
                      .map(
                        (row) => DropdownMenuItem<String>(
                          value: row['id'].toString(),
                          child: Text(row['registration'].toString()),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => refresh(() => target = value),
                ),
                TextField(
                  controller: reason,
                  maxLength: 1000,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: _phrase(
                      'Why do you need to change?',
                      'Dlaczego chcesz zmienić vana?',
                    ),
                  ),
                ),
                Text(
                  _phrase(
                    'A manager must approve this request.',
                    'Zmiana wymaga zgody managera.',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(_phrase('Cancel', 'Anuluj')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, {
                'target': target ?? '',
                'reason': reason.text.trim(),
              }),
              child: Text(_phrase('Request', 'Wyślij prośbę')),
            ),
          ],
        ),
      ),
    );
    reason.dispose();
    if (answer == null || !mounted) return;
    if (answer['target']!.isEmpty || answer['reason']!.length < 3) {
      _message(
        _phrase(
          'Select a van and explain why you need it.',
          'Wybierz vana i podaj powód zmiany.',
        ),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await _client.rpc(
        'fleetpilot_request_vehicle_change',
        params: {
          '_company_id': widget.company.companyId,
          '_to_vehicle_id': answer['target'],
          '_reason': answer['reason'],
        },
      );
      if (mounted) setState(_reload);
      _message(
        _phrase(
          'Request sent. Wait for manager approval.',
          'Prośba wysłana. Poczekaj na zatwierdzenie przez managera.',
        ),
      );
    } catch (error) {
      _message(
        '${_phrase('Request failed', 'Nie udało się wysłać prośby')}: $error',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelRequest(String id) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _client.rpc(
        'fleetpilot_cancel_vehicle_change',
        params: {'_request_id': id},
      );
      if (mounted) setState(_reload);
    } catch (error) {
      _message('$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _walkaround(_DriverData data) async {
    if (!data.enabled || data.profile == null || data.vehicle == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _DriverWalkaround(
          companyId: widget.company.companyId,
          driverId: data.profile!['id'].toString(),
          vehicleId: data.vehicle!['id'].toString(),
          registration: data.vehicle!['registration'].toString(),
        ),
      ),
    );
    if (mounted) setState(_reload);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('${widget.company.companyName} — Driver'),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () => setState(_reload),
        ),
        IconButton(
          icon: const Icon(Icons.logout),
          onPressed: () => _client.auth.signOut(),
        ),
      ],
    ),
    body: FutureBuilder<_DriverData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                '${_phrase('Loading failed', 'Błąd ładowania')}: ${snapshot.error}',
              ),
            ),
          );
        }
        final data = snapshot.data!;
        final vehicle = data.vehicle;
        return RefreshIndicator(
          onRefresh: () async {
            setState(_reload);
            await _future;
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
            children: [
              Text(
                _phrase('My van', 'Mój van'),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 12),
              if (!data.enabled)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      _phrase(
                        'Driver Mode is not enabled in this fleet plan.',
                        'Tryb kierowcy nie jest dostępny w tym planie floty.',
                      ),
                    ),
                  ),
                ),
              if (data.profile == null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      _phrase(
                        'Ask your manager to link your FleetPilot account to your driver record. The email addresses must match.',
                        'Poproś managera o powiązanie konta FleetPilot z kartą kierowcy. Adresy e-mail muszą się zgadzać.',
                      ),
                    ),
                  ),
                ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: vehicle == null
                      ? Text(
                          _phrase(
                            'No van is assigned yet.',
                            'Nie masz jeszcze przypisanego vana.',
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              vehicle['registration'].toString(),
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              [vehicle['make'], vehicle['model']]
                                  .where(
                                    (v) => v != null && v.toString().isNotEmpty,
                                  )
                                  .join(' '),
                            ),
                            Text(
                              '${_phrase('Odometer', 'Przebieg')}: ${vehicle['mileage']} mi',
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _busy || !data.enabled || vehicle == null
                    ? null
                    : () => _walkaround(data),
                icon: const Icon(Icons.fact_check_outlined),
                label: Text(
                  _phrase(
                    'Pre/post-trip van check',
                    'Kontrola vana przed / po trasie',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _busy || !data.enabled || vehicle == null
                    ? null
                    : () => _reportIssue(data),
                icon: const Icon(Icons.report_problem_outlined),
                label: Text(_phrase('Report a defect', 'Zgłoś usterkę')),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _busy || !data.enabled || data.profile == null
                    ? null
                    : () => _requestChange(data),
                icon: const Icon(Icons.swap_horiz),
                label: Text(
                  _phrase('Request van change', 'Poproś o zmianę vana'),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                _phrase('Van change requests', 'Prośby o zmianę vana'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (data.changes.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _phrase('No requests yet.', 'Nie masz jeszcze próśb.'),
                  ),
                ),
              for (final change in data.changes)
                Card(
                  child: ListTile(
                    title: Text(
                      '${change['from_registration'] ?? '—'} → ${change['to_registration']}',
                    ),
                    subtitle: Text('${change['status']} • ${change['reason']}'),
                    trailing: change['status'] == 'pending'
                        ? IconButton(
                            icon: const Icon(Icons.close),
                            tooltip: _phrase('Cancel request', 'Anuluj prośbę'),
                            onPressed: _busy
                                ? null
                                : () => _cancelRequest(change['id'].toString()),
                          )
                        : const Icon(Icons.history),
                  ),
                ),
              const SizedBox(height: 18),
              Text(
                _phrase('My van defect reports', 'Usterki mojego vana'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (data.issues.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _phrase('No defects to show.', 'Brak zgłoszonych usterek.'),
                  ),
                ),
              for (final issue in data.issues)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.build_outlined),
                    title: Text(issue['title'].toString()),
                    subtitle: Text(
                      '${issue['status']} • ${issue['priority']}\n${issue['description'] ?? ''}',
                    ),
                    isThreeLine: true,
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );
}

class _DriverData {
  _DriverData({
    required this.enabled,
    required this.profile,
    required this.vehicle,
    required this.issues,
    required this.changes,
    required this.options,
  });
  final bool enabled;
  final Map<String, dynamic>? profile;
  final Map<String, dynamic>? vehicle;
  final List<Map<String, dynamic>> issues;
  final List<Map<String, dynamic>> changes;
  final List<Map<String, dynamic>> options;
}

class _DriverWalkaround extends StatefulWidget {
  const _DriverWalkaround({
    required this.companyId,
    required this.driverId,
    required this.vehicleId,
    required this.registration,
  });
  final String companyId, driverId, vehicleId, registration;

  @override
  State<_DriverWalkaround> createState() => _DriverWalkaroundState();
}

class _DriverWalkaroundState extends State<_DriverWalkaround> {
  final _client = Supabase.instance.client;
  final _notes = TextEditingController();
  final _odometer = TextEditingController();
  final _answers = <String, bool?>{
    for (final item in driverCheckItems) item: null,
  };
  bool _unsafe = false;
  bool _busy = false;
  String _type = 'pre_trip';

  @override
  void dispose() {
    _notes.dispose();
    _odometer.dispose();
    super.dispose();
  }

  void _message(String message) {
    if (mounted)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save() async {
    if (_busy) return;
    final result = driverCheckResult(_answers, unsafe: _unsafe);
    if (result == null) {
      _message(_phrase('Check all items.', 'Sprawdź wszystkie punkty.'));
      return;
    }
    if (result != 'pass' && _notes.text.trim().isEmpty) {
      _message(_phrase('Describe the defect.', 'Opisz usterkę.'));
      return;
    }
    final reading = _odometer.text.trim();
    final mileage = reading.isEmpty ? null : int.tryParse(reading);
    if (reading.isNotEmpty && mileage == null) {
      _message(_phrase('Invalid odometer.', 'Nieprawidłowy przebieg.'));
      return;
    }
    setState(() => _busy = true);
    try {
      await _client.from('driver_vehicle_checks').insert({
        'company_id': widget.companyId,
        'vehicle_id': widget.vehicleId,
        'driver_id': widget.driverId,
        'created_by': _client.auth.currentUser!.id,
        'check_type': _type,
        'result': result,
        'odometer': mileage,
        'checks': {
          for (final answer in _answers.entries) answer.key: answer.value!,
        },
        'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      });
      if (mounted) {
        _message(
          result == 'pass'
              ? _phrase('Check saved.', 'Kontrola zapisana.')
              : _phrase(
                  'Defect reported to your manager.',
                  'Usterka zgłoszona managerowi.',
                ),
        );
        Navigator.pop(context);
      }
    } catch (error) {
      _message(
        '${_phrase('Unable to save check', 'Nie udało się zapisać kontroli')}: $error',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('${widget.registration} — ${_phrase('Check', 'Kontrola')}'),
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        DropdownButtonFormField<String>(
          initialValue: _type,
          items: [
            DropdownMenuItem(
              value: 'pre_trip',
              child: Text(_phrase('Before route', 'Przed trasą')),
            ),
            DropdownMenuItem(
              value: 'post_trip',
              child: Text(_phrase('After route', 'Po trasie')),
            ),
          ],
          onChanged: _busy
              ? null
              : (value) => setState(() => _type = value ?? 'pre_trip'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _odometer,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: _phrase('Odometer (miles)', 'Przebieg (mile)'),
          ),
        ),
        const SizedBox(height: 14),
        for (final item in driverCheckItems)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr('check_item_$item'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: Text(_phrase('OK', 'OK')),
                        selected: _answers[item] == true,
                        onSelected: _busy
                            ? null
                            : (_) => setState(() => _answers[item] = true),
                      ),
                      ChoiceChip(
                        label: Text(_phrase('Defect', 'Usterka')),
                        selected: _answers[item] == false,
                        onSelected: _busy
                            ? null
                            : (_) => setState(() => _answers[item] = false),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        SwitchListTile(
          title: Text(
            _phrase('Unsafe to drive', 'Pojazd niebezpieczny do jazdy'),
          ),
          value: _unsafe,
          onChanged: _busy || !_answers.values.contains(false)
              ? null
              : (value) => setState(() => _unsafe = value),
        ),
        TextField(
          controller: _notes,
          maxLines: 3,
          maxLength: 1000,
          decoration: InputDecoration(
            labelText: _phrase('Details of any defect', 'Opis usterki'),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          icon: const Icon(Icons.check),
          onPressed: _busy ? null : _save,
          label: Text(_phrase('Submit check', 'Zapisz kontrolę')),
        ),
      ],
    ),
  );
}
