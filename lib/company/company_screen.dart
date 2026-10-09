import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/constants.dart';
import '../core/formatters.dart';
import '../core/localization.dart';
import '../data/fleet_repository.dart';
import '../data/models.dart';

class CompanyScreen extends StatefulWidget {
  const CompanyScreen({
    required this.company,
    required this.onMembershipChanged,
    super.key,
  });

  final CompanyMembership company;
  final Future<void> Function() onMembershipChanged;

  @override
  State<CompanyScreen> createState() => _CompanyScreenState();
}

class _CompanyScreenState extends State<CompanyScreen> {
  final _repository = FleetRepository();
  final _inviteCode = TextEditingController();

  late Future<List<CompanyMember>> _members;
  Future<List<CompanyInvite>>? _invites;

  bool get _canAdmin =>
      widget.company.role == 'owner' || widget.company.role == 'admin';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant CompanyScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.company.companyId != widget.company.companyId) {
      _reload();
    }
  }

  @override
  void dispose() {
    _inviteCode.dispose();
    super.dispose();
  }

  void _reload() {
    _members = _repository.fetchCompanyMembers(widget.company.companyId);

    if (_canAdmin) {
      _invites = _repository.fetchCompanyInvites(widget.company.companyId);
    } else {
      _invites = null;
    }
  }

  Future<void> _changeLanguage(String value) async {
    await _repository.updateUserLocale(value);
    AppLocale.language.value = value;

    if (mounted) setState(() {});
  }

  Future<void> _createInvite() async {
    final email = TextEditingController();
    var role = 'manager';

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(tr('invite_member')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(labelText: tr('email')),
                ),
                SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: role,
                  decoration: InputDecoration(labelText: tr('role')),
                  items: [
                    DropdownMenuItem(value: 'admin', child: Text(tr('admin'))),
                    DropdownMenuItem(
                      value: 'manager',
                      child: Text(tr('manager')),
                    ),
                    DropdownMenuItem(
                      value: 'viewer',
                      child: Text(tr('viewer')),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => role = value);
                    }
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(tr('cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, {
                  'email': email.text.trim(),
                  'role': role,
                }),
                child: Text(tr('create_invite')),
              ),
            ],
          );
        },
      ),
    );

    email.dispose();

    if (result == null || result['email']!.isEmpty) {
      return;
    }

    try {
      final code = await _repository.createCompanyInvite(
        companyId: widget.company.companyId,
        email: result['email']!,
        role: result['role']!,
      );

      final params = Map<String, String>.from(Uri.base.queryParameters);

      params['invite'] = code;

      final link = Uri.base.replace(queryParameters: params).toString();

      await Clipboard.setData(ClipboardData(text: link));

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(tr('invite_created'))));

      setState(_reload);
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _acceptCode() async {
    final code = _inviteCode.text.trim();

    if (code.isEmpty) return;

    try {
      await _repository.acceptCompanyInvite(code);

      _inviteCode.clear();

      await widget.onMembershipChanged();

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(tr('company_added'))));
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _updateRole(CompanyMember member, String role) async {
    await _repository.updateCompanyMemberRole(
      companyId: widget.company.companyId,
      userId: member.userId,
      role: role,
    );

    setState(_reload);
  }

  Future<void> _removeMember(CompanyMember member) async {
    await _repository.removeCompanyMember(
      companyId: widget.company.companyId,
      userId: member.userId,
    );

    setState(_reload);
  }

  Future<void> _revokeInvite(CompanyInvite invite) async {
    await _repository.revokeCompanyInvite(invite.id);

    setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = _repository.currentUser?.id;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
      children: [
        Text(tr('company'), style: Theme.of(context).textTheme.headlineMedium),
        SizedBox(height: 16),

        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.company.companyName,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                SizedBox(height: 8),
                Text(
                  '${tr('your_role')}: ${prettifyEnum(widget.company.role)}',
                ),
                Text('${tr('currency')}: ${widget.company.currency}'),
              ],
            ),
          ),
        ),

        SizedBox(height: 16),

        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                const Icon(Icons.language_rounded),
                SizedBox(width: 14),
                Expanded(
                  child: Text(
                    tr('language'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                DropdownButton<String>(
                  value: AppLocale.language.value,
                  items: supportedLanguages
                      .map(
                        (code) => DropdownMenuItem<String>(
                          value: code,
                          child: Text(languageLabel(code)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      _changeLanguage(value);
                    }
                  },
                ),
              ],
            ),
          ),
        ),

        SizedBox(height: 24),

        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr('team'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  SizedBox(height: 3),
                  Text(tr('team_description')),
                ],
              ),
            ),
            if (_canAdmin)
              FilledButton.icon(
                onPressed: _createInvite,
                icon: const Icon(Icons.person_add),
                label: Text(tr('invite_member')),
              ),
          ],
        ),

        SizedBox(height: 12),

        FutureBuilder<List<CompanyMember>>(
          future: _members,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return Card(
                child: Padding(
                  padding: EdgeInsets.all(30),
                  child: Center(child: CircularProgressIndicator()),
                ),
              );
            }

            final members = snapshot.data!;

            return Card(
              child: Column(
                children: [
                  for (var i = 0; i < members.length; i++) ...[
                    ListTile(
                      leading: CircleAvatar(
                        child: Text(
                          (members[i].displayName ?? members[i].email).isEmpty
                              ? '?'
                              : (members[i].displayName ?? members[i].email)[0]
                                    .toUpperCase(),
                        ),
                      ),
                      title: Text(members[i].displayName ?? members[i].email),
                      subtitle: Text(
                        '${members[i].email} • ${formatDate(members[i].joinedAt)}',
                      ),
                      trailing: members[i].role == 'owner'
                          ? Text(tr('owner'))
                          : _canAdmin && members[i].userId != currentUserId
                          ? PopupMenuButton<String>(
                              onSelected: (value) {
                                if (value == 'remove') {
                                  _removeMember(members[i]);
                                } else {
                                  _updateRole(members[i], value);
                                }
                              },
                              itemBuilder: (_) => [
                                PopupMenuItem(
                                  value: 'admin',
                                  child: Text(tr('admin')),
                                ),
                                PopupMenuItem(
                                  value: 'manager',
                                  child: Text(tr('manager')),
                                ),
                                PopupMenuItem(
                                  value: 'viewer',
                                  child: Text(tr('viewer')),
                                ),
                                const PopupMenuDivider(),
                                PopupMenuItem(
                                  value: 'remove',
                                  child: Text(tr('remove')),
                                ),
                              ],
                              child: Text(prettifyEnum(members[i].role)),
                            )
                          : Text(prettifyEnum(members[i].role)),
                    ),
                    if (i != members.length - 1) const Divider(height: 1),
                  ],
                ],
              ),
            );
          },
        ),

        if (_canAdmin && _invites != null) ...[
          SizedBox(height: 24),
          Text(
            tr('pending_invites'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          SizedBox(height: 10),
          FutureBuilder<List<CompanyInvite>>(
            future: _invites,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return SizedBox(
                  height: 40,
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              final invites = snapshot.data!
                  .where((invite) => invite.status == 'pending')
                  .toList();

              if (invites.isEmpty) {
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Text(tr('no_invites')),
                  ),
                );
              }

              return Card(
                child: Column(
                  children: [
                    for (var i = 0; i < invites.length; i++) ...[
                      ListTile(
                        leading: const Icon(Icons.mail_outline_rounded),
                        title: Text(invites[i].email),
                        subtitle: Text(
                          '${prettifyEnum(invites[i].role)} • ${formatDate(invites[i].expiresAt)}',
                        ),
                        trailing: TextButton(
                          onPressed: () => _revokeInvite(invites[i]),
                          child: Text(tr('revoke')),
                        ),
                      ),
                      if (i != invites.length - 1) const Divider(height: 1),
                    ],
                  ],
                ),
              );
            },
          ),
        ],

        SizedBox(height: 24),

        Text(tr('join_company'), style: Theme.of(context).textTheme.titleLarge),

        SizedBox(height: 10),

        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _inviteCode,
                    decoration: InputDecoration(labelText: tr('invite_code')),
                  ),
                ),
                SizedBox(width: 10),
                FilledButton(
                  onPressed: _acceptCode,
                  child: Text(tr('accept_invite')),
                ),
              ],
            ),
          ),
        ),

        SizedBox(height: 24),

        OutlinedButton.icon(
          onPressed: () => _repository.signOut(),
          icon: const Icon(Icons.logout),
          label: Text(tr('sign_out')),
        ),
      ],
    );
  }
}
