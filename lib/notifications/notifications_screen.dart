import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants.dart';
import '../core/formatters.dart';
import '../core/localization.dart';
import '../data/models.dart';
import '../vehicles/vehicle_detail_screen.dart';

/// Tenant-filtered inbox. Supabase RLS separately enforces recipient access.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({required this.company, super.key});

  final CompanyMembership company;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final SupabaseClient _client = Supabase.instance.client;
  late Future<_InboxData> _future;
  bool _unreadOnly = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = _fetch();
  }

  Future<_InboxData> _fetch() async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError(tr('notification_sign_in'));

    final notifications = await _client
        .from('fleet_notifications')
        .select(
          'id,vehicle_id,kind,registration,due_date,due_mileage,stage,read_at,created_at',
        )
        .eq('company_id', widget.company.companyId)
        .eq('recipient_user_id', user.id)
        .order('created_at', ascending: false)
        .limit(200);

    final preferences = await _client
        .from('fleet_notification_preferences')
        .select(
          'in_app_enabled,email_enabled,mot_enabled,insurance_enabled,service_enabled',
        )
        .eq('company_id', widget.company.companyId)
        .eq('user_id', user.id)
        .maybeSingle();

    return _InboxData(
      entries: (notifications as List)
          .map((entry) => Map<String, dynamic>.from(entry as Map))
          .toList(),
      preferences: Map<String, dynamic>.from(preferences ?? {}),
      userId: user.id,
    );
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${tr('notification_error')}: $error')),
    );
  }

  Future<void> _markRead(Map<String, dynamic> item, _InboxData data) async {
    if (item['read_at'] != null) return;
    try {
      await _client
          .from('fleet_notifications')
          .update({'read_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', item['id'].toString())
          .eq('company_id', widget.company.companyId)
          .eq('recipient_user_id', data.userId);
      if (mounted) setState(_reload);
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _openVehicle(Map<String, dynamic> item, _InboxData data) async {
    await _markRead(item, data);
    if (!mounted) return;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => VehicleDetailScreen(
          company: widget.company,
          vehicleId: item['vehicle_id'].toString(),
          canManage: canManageForRole(widget.company.role),
        ),
      ),
    );
    if (mounted) setState(_reload);
  }

  Future<void> _savePreference(_InboxData data, String key, bool value) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final updated = <String, dynamic>{
        'company_id': widget.company.companyId,
        'user_id': data.userId,
        'in_app_enabled': data.preferences['in_app_enabled'] ?? true,
        'email_enabled': data.preferences['email_enabled'] ?? false,
        'mot_enabled': data.preferences['mot_enabled'] ?? true,
        'insurance_enabled': data.preferences['insurance_enabled'] ?? true,
        'service_enabled': data.preferences['service_enabled'] ?? true,
        key: value,
      };
      await _client
          .from('fleet_notification_preferences')
          .upsert(updated, onConflict: 'company_id,user_id');
      if (mounted) setState(_reload);
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _kindLabel(String kind) => switch (kind) {
    'mot' => tr('notification_mot'),
    'insurance' => tr('notification_insurance'),
    'service_date' => tr('notification_service_date'),
    'service_mileage' => tr('notification_service_mileage'),
    _ => kind,
  };

  String _description(Map<String, dynamic> item) {
    final stage = (item['stage'] as num?)?.toInt() ?? 0;
    if (item['kind'] == 'service_mileage') {
      final target = (item['due_mileage'] as num?)?.toInt();
      final label = stage < 0
          ? tr('notification_overdue')
          : stage == 0
          ? tr('notification_due_now')
          : tr('notification_mileage_window');
      return '$label • ${tr('notification_target')}: ${formatMileage(target)} mi';
    }
    final due = parseDate(item['due_date']);
    final label = stage < 0
        ? tr('notification_overdue')
        : stage == 0
        ? tr('notification_due_today')
        : '${tr('notification_within')} $stage ${tr('notification_days')}';
    return '$label • ${tr('notification_due')}: ${formatDate(due)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('notifications')),
        actions: [
          IconButton(
            tooltip: tr('refresh'),
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(_reload),
          ),
        ],
      ),
      body: FutureBuilder<_InboxData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      snapshot.error.toString(),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => setState(_reload),
                      child: Text(tr('try_again')),
                    ),
                  ],
                ),
              ),
            );
          }

          final data = snapshot.data!;
          final unread = data.entries
              .where((item) => item['read_at'] == null)
              .length;
          final visible = data.entries
              .where((item) => !_unreadOnly || item['read_at'] == null)
              .toList();

          Widget setting(String key, String label) {
            final enabled =
                data.preferences[key] as bool? ?? (key != 'email_enabled');
            return SwitchListTile.adaptive(
              title: Text(label),
              value: enabled,
              onChanged: _saving
                  ? null
                  : (value) => _savePreference(data, key, value),
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              setState(_reload);
              await _future;
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
              children: [
                Text(
                  tr('notification_inbox'),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  children: [
                    ChoiceChip(
                      label: Text(tr('notification_all')),
                      selected: !_unreadOnly,
                      onSelected: (_) => setState(() => _unreadOnly = false),
                    ),
                    ChoiceChip(
                      label: Text('${tr('notification_unread')} ($unread)'),
                      selected: _unreadOnly,
                      onSelected: (_) => setState(() => _unreadOnly = true),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (visible.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(tr('notification_empty')),
                    ),
                  )
                else
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (var i = 0; i < visible.length; i++) ...[
                          ListTile(
                            leading: Icon(
                              visible[i]['read_at'] == null
                                  ? Icons.notifications_active_outlined
                                  : Icons.notifications_none_outlined,
                              color: visible[i]['read_at'] == null
                                  ? Theme.of(context).colorScheme.primary
                                  : null,
                            ),
                            title: Text(
                              '${visible[i]['registration']} — ${_kindLabel(visible[i]['kind'].toString())}',
                              style: TextStyle(
                                fontWeight: visible[i]['read_at'] == null
                                    ? FontWeight.w700
                                    : FontWeight.normal,
                              ),
                            ),
                            subtitle: Text(_description(visible[i])),
                            isThreeLine: false,
                            onTap: () => _openVehicle(visible[i], data),
                            trailing: visible[i]['read_at'] == null
                                ? IconButton(
                                    tooltip: tr('notification_mark_read'),
                                    icon: const Icon(Icons.done),
                                    onPressed: () =>
                                        _markRead(visible[i], data),
                                  )
                                : const Icon(Icons.chevron_right),
                          ),
                          if (i != visible.length - 1) const Divider(height: 1),
                        ],
                      ],
                    ),
                  ),
                const SizedBox(height: 24),
                Text(
                  tr('notification_preferences'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: [
                      setting('in_app_enabled', tr('notification_in_app')),
                      const Divider(height: 1),
                      setting('mot_enabled', tr('notification_mot')),
                      setting(
                        'insurance_enabled',
                        tr('notification_insurance'),
                      ),
                      setting('service_enabled', tr('notification_service')),
                      const Divider(height: 1),
                      setting('email_enabled', tr('notification_email')),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  tr('notification_test_email_only'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _InboxData {
  const _InboxData({
    required this.entries,
    required this.preferences,
    required this.userId,
  });

  final List<Map<String, dynamic>> entries;
  final Map<String, dynamic> preferences;
  final String userId;
}
