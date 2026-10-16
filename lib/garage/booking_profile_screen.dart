import 'package:flutter/material.dart';

import '../core/localization.dart';
import 'booking_status_text.dart';
import 'consumer_booking_repository.dart';
import 'garage_ui_text.dart';

typedef BookingProfileSaver = Future<bool> Function({required String city,
  required String timeZone, required List<String> services,
  required int durationMinutes, required bool listed});

/// Owner-only QA configuration. A public listing never promises a free slot.
class GarageBookingProfileScreen extends StatefulWidget {
  const GarageBookingProfileScreen({required this.load, required this.save, super.key});
  factory GarageBookingProfileScreen.forRepository({required GarageBookingRepository repository,
      required String workspaceId}) => GarageBookingProfileScreen(
    load: () => repository.profile(workspaceId),
    save: ({required city, required timeZone, required services,
      required durationMinutes, required listed}) => repository.configure(
        workspaceId: workspaceId, city: city, timeZone: timeZone,
        services: services, durationMinutes: durationMinutes, listed: listed));
  final Future<GarageBookingProfile?> Function() load;
  final BookingProfileSaver save;
  @override
  State<GarageBookingProfileScreen> createState() => _ProfileState();
}

class _ProfileState extends State<GarageBookingProfileScreen> {
  final _city = TextEditingController();
  final _zone = TextEditingController();
  Set<String> _services = {};
  int _duration = 60;
  bool _listed = false;
  bool _busy = true;
  bool _loaded = false;
  bool _uncertain = false;
  String? _notice;
  int _version = 0;
  int _scope = 0;
  @override
  void initState() { super.initState(); _load(); }
  @override
  void didUpdateWidget(covariant GarageBookingProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.load != widget.load || oldWidget.save != widget.save) {
      _scope++; _load();
    }
  }
  @override
  void dispose() { _scope++; _version++; _city.dispose(); _zone.dispose(); super.dispose(); }

  Future<void> _load() async {
    final version = ++_version;
    final load = widget.load;
    setState(() {
      _busy = true; _loaded = false; _notice = null;
      _city.clear(); _zone.clear(); _services = {}; _listed = false; _duration = 60;
    });
    try {
      final profile = await load();
      if (!mounted || version != _version) return;
      setState(() {
        _city.text = profile?.city ?? '';
        _zone.text = profile?.timeZone ?? 'Europe/London';
        _services = profile?.services.toSet() ?? {};
        _duration = profile?.durationMinutes ?? 60;
        _listed = profile?.listed ?? false;
        _loaded = true; _uncertain = false;
      });
    } catch (_) {
      if (mounted && version == _version) setState(() => _notice = GarageUiText.get('accessFailed'));
    } finally {
      if (mounted && version == _version) setState(() => _busy = false);
    }
  }

  bool get _valid => _city.text.trim().length >= 2 && _city.text.trim().length <= 80 &&
      _zone.text.trim().isNotEmpty && _zone.text.trim().length <= 100 && _services.isNotEmpty;

  Future<void> _save() async {
    if (_busy || !_loaded || _uncertain || !_valid) return;
    final scope = _scope;
    final version = _version;
    final save = widget.save;
    final city = _city.text.trim(), zone = _zone.text.trim();
    final services = List<String>.unmodifiable(_services);
    final duration = _duration, listed = _listed;
    final confirmed = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: Text(GarageUiText.get('bookingProfile')),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
        children: [Text(GarageUiText.get('bookingProfileHint')),
          const SizedBox(height: 12),
          Text('${GarageUiText.get('bookingListed')}: ${listed ? tr('active') : tr('inactive')}')]),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false),
        child: Text(GarageUiText.get('quoteBack'))),
        FilledButton(key: const Key('booking_profile_confirm'),
          onPressed: () => Navigator.pop(c, true),
          child: Text(GarageUiText.get('bookingSave')))]));
    if (!mounted || scope != _scope || version != _version || confirmed != true || _busy) return;
    setState(() { _busy = true; _notice = null; });
    try {
      if (!await save(city: city, timeZone: zone, services: services,
          durationMinutes: duration, listed: listed)) throw const FormatException('Save not confirmed');
      if (!mounted || scope != _scope) return;
      await _load();
      if (mounted && scope == _scope && _loaded) {
        setState(() => _notice = GarageUiText.get('bookingSaved'));
      }
    } catch (_) {
      if (mounted && scope == _scope) setState(() {
        _uncertain = true; _loaded = false;
        _city.clear(); _zone.clear(); _services = {}; _listed = false;
        _notice = GarageUiText.get('bookingSaveUncertain');
      });
    } finally {
      if (mounted && scope == _scope) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = !_busy && _loaded && !_uncertain;
    return Scaffold(appBar: AppBar(title: Text(GarageUiText.get('bookingProfile')),
      actions: [IconButton(key: const Key('booking_profile_reload'),
        onPressed: _busy ? null : _load, icon: const Icon(Icons.refresh))]),
      body: SafeArea(child: _busy ? const Center(child: CircularProgressIndicator())
        : ListView(padding: const EdgeInsets.all(20), children: [
          Text(GarageUiText.get('bookingProfileHint')),
          if (_notice != null) Text(_notice!, key: const Key('booking_profile_notice')),
          if (_loaded) ...[
            TextField(key: const Key('booking_profile_city'), controller: _city,
              enabled: enabled, maxLength: 80, onChanged: (_) => setState(() {}),
              decoration: InputDecoration(labelText: tr('city'))),
            TextField(key: const Key('booking_profile_zone'), controller: _zone,
              enabled: enabled, maxLength: 100, onChanged: (_) => setState(() {}),
              decoration: InputDecoration(labelText: GarageUiText.get('bookingTimeZone'),
                hintText: 'Europe/London')),
            Wrap(spacing: 8, children: [for (final service in GarageBookingService.values)
              FilterChip(key: Key('booking_profile_service_$service'),
                label: Text(bookingServiceLabel(service)), selected: _services.contains(service),
                onSelected: enabled ? (selected) => setState(() {
                  if (selected) { _services.add(service); } else { _services.remove(service); }
                }) : null)]),
            DropdownButtonFormField<int>(key: const Key('booking_profile_duration'),
              initialValue: _duration, decoration: const InputDecoration(labelText: 'min'),
              items: [for (final value in [30, 60, 90, 120]) DropdownMenuItem(value: value, child: Text('$value min'))],
              onChanged: enabled ? (value) { if (value != null) setState(() => _duration = value); } : null),
            SwitchListTile(key: const Key('booking_profile_listed'), value: _listed,
              title: Text(GarageUiText.get('bookingListed')),
              onChanged: enabled ? (value) => setState(() => _listed = value) : null),
            FilledButton(key: const Key('booking_profile_save'),
              onPressed: enabled && _valid ? _save : null,
              child: Text(GarageUiText.get('bookingSave'))),
          ],
        ])));
  }
}
