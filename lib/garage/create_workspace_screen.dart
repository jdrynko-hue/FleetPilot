import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/billing_markets.dart';
import '../core/localization.dart';
import 'garage_ui_text.dart';
import 'workspace_repository.dart';

typedef GarageWorkspaceCreator = Future<void> Function({
  required String name, required String country});

/// QA-only entry; private customers are never required to create a business.
class GarageCreateWorkspaceScreen extends StatefulWidget {
  const GarageCreateWorkspaceScreen({required this.create,
    required this.isCurrentAccount, required this.onCreated, super.key});
  factory GarageCreateWorkspaceScreen.forClient({required SupabaseClient client,
      required VoidCallback onCreated}) {
    final userId = client.auth.currentUser?.id;
    return GarageCreateWorkspaceScreen(
      create: GarageWorkspaceRepository(client).create,
      isCurrentAccount: () => userId != null && client.auth.currentUser?.id == userId,
      onCreated: onCreated);
  }
  final GarageWorkspaceCreator create;
  final bool Function() isCurrentAccount;
  final VoidCallback onCreated;
  @override
  State<GarageCreateWorkspaceScreen> createState() => _CreateWorkspaceState();
}

class _CreateWorkspaceState extends State<GarageCreateWorkspaceScreen> {
  final _name = TextEditingController();
  String _country = 'GB';
  bool _business = false;
  bool _busy = false;
  bool _uncertain = false;
  int _scope = 0;

  @override
  void didUpdateWidget(covariant GarageCreateWorkspaceScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.create != widget.create ||
        oldWidget.isCurrentAccount != widget.isCurrentAccount) {
      _scope++;
      _name.clear(); _country = 'GB'; _business = false;
      _busy = false; _uncertain = false;
    }
  }
  @override
  void dispose() { _scope++; _name.dispose(); super.dispose(); }

  Future<void> _create() async {
    if (_busy || _uncertain || !_business || !widget.isCurrentAccount() ||
        _name.text.trim().length < 2 || _name.text.trim().length > 160) return;
    final scope = _scope;
    final currentAccount = widget.isCurrentAccount;
    final create = widget.create;
    setState(() => _busy = true);
    try {
      await create(name: _name.text.trim(), country: _country);
      if (mounted && scope == _scope && currentAccount()) widget.onCreated();
    } catch (_) {
      // A timeout can follow a successful insert. Require membership refresh
      // before another attempt; do not automatically retry workspace creation.
      if (mounted && scope == _scope && currentAccount()) {
        setState(() => _uncertain = true);
      }
    } finally {
      if (mounted && scope == _scope) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = !_busy && !_uncertain;
    return Scaffold(
      appBar: AppBar(title: Text(GarageUiText.get('createWorkshop'))),
      body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 600),
        child: ListView(padding: const EdgeInsets.all(20), children: [
          Text(GarageUiText.get('workshopSetupIntro')),
          const SizedBox(height: 16),
          TextField(key: const Key('garage_create_name'), controller: _name,
            enabled: enabled, maxLength: 160, onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: GarageUiText.get('workshopName'))),
          DropdownButtonFormField<String>(key: const Key('garage_create_country'),
            initialValue: _country, isExpanded: true,
            decoration: InputDecoration(labelText: tr('country')),
            items: supportedFleetCountries.keys.map((code) => DropdownMenuItem(
              value: code, child: Text(fleetCountryName(code,
                locale: AppLocale.language.value), overflow: TextOverflow.ellipsis))).toList(),
            onChanged: enabled ? (value) {
              if (value != null) setState(() => _country = value);
            } : null),
          const SizedBox(height: 12),
          Text('${tr('currency')}: ${currencyForFleetCountry(_country)}',
            key: const Key('garage_create_currency')),
          CheckboxListTile(key: const Key('garage_create_business'), value: _business,
            contentPadding: EdgeInsets.zero,
            title: Text(tr('b2b_confirmation')), subtitle: Text(tr('b2b_only')),
            onChanged: enabled ? (value) => setState(() => _business = value ?? false) : null),
          if (_uncertain) Text(GarageUiText.get('workshopCreateUncertain'),
            key: const Key('garage_create_uncertain')),
          FilledButton(key: const Key('garage_create_submit'),
            onPressed: enabled && _business && _name.text.trim().length >= 2 ? _create : null,
            child: Text(_busy ? tr('creating') : GarageUiText.get('createWorkshop'))),
        ]))),
    );
  }
}
