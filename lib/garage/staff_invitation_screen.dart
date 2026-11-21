import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/localization.dart';
import 'workspace_repository.dart';

class GarageStaffInvitationScreen extends StatefulWidget {
  const GarageStaffInvitationScreen({
    required this.isCurrentAccount,
    required this.submit,
    required this.issue,
    super.key,
  });

  final bool Function() isCurrentAccount;
  final Future<String> Function(String value, String role) submit;
  final bool issue;

  static String title(bool issue) => _copy(
    issue ? 'Zaproś pracownika' : 'Przyjmij zaproszenie do warsztatu',
    issue ? 'Invite workshop staff' : 'Accept a workshop invitation',
  );

  static String _copy(String pl, String en) =>
      AppLocale.language.value == 'pl' ? pl : en;

  @override
  State<GarageStaffInvitationScreen> createState() =>
      _GarageStaffInvitationScreenState();
}

class _GarageStaffInvitationScreenState
    extends State<GarageStaffInvitationScreen> {
  final _input = TextEditingController();
  String _role = 'mechanic';
  String? _code;
  bool _busy = false;
  bool _failed = false;

  String _copy(String pl, String en) =>
      GarageStaffInvitationScreen._copy(pl, en);

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || _code != null || !widget.isCurrentAccount()) return;
    final value = _input.text.trim();
    final valid = widget.issue
        ? RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value)
        : GarageWorkspaceRepository.invitationCode.hasMatch(value);
    if (!valid) {
      setState(() => _failed = true);
      return;
    }

    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final result = await widget.submit(value, _role);
      if (!mounted || !widget.isCurrentAccount()) return;
      if (widget.issue) {
        _input.clear();
        setState(() => _code = result);
      } else {
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted && widget.isCurrentAccount()) {
        setState(() => _failed = true);
      }
    } finally {
      if (mounted && widget.isCurrentAccount()) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final code = _code;
    return Scaffold(
      appBar: AppBar(
        title: Text(GarageStaffInvitationScreen.title(widget.issue)),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (code == null) ...[
                TextField(
                  key: const Key('garage_staff_invitation_input'),
                  controller: _input,
                  enabled: !_busy,
                  autocorrect: false,
                  enableSuggestions: false,
                  maxLength: widget.issue ? 254 : 32,
                  keyboardType: widget.issue
                      ? TextInputType.emailAddress
                      : TextInputType.text,
                  decoration: InputDecoration(
                    labelText: widget.issue
                        ? _copy('E-mail pracownika', 'Staff email')
                        : _copy('Kod zaproszenia', 'Invitation code'),
                  ),
                ),
                if (widget.issue)
                  DropdownButtonFormField<String>(
                    initialValue: _role,
                    decoration: InputDecoration(
                      labelText: _copy('Rola', 'Role'),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'mechanic',
                        child: Text(_copy('Mechanik', 'Mechanic')),
                      ),
                      DropdownMenuItem(
                        value: 'service_adviser',
                        child: Text(
                          _copy('Doradca serwisowy', 'Service adviser'),
                        ),
                      ),
                    ],
                    onChanged: _busy
                        ? null
                        : (value) {
                            if (value != null) setState(() => _role = value);
                          },
                  ),
                if (_failed)
                  Text(
                    widget.issue
                        ? _copy(
                            'Nie udało się potwierdzić utworzenia zaproszenia.',
                            'Could not confirm that the invitation was created.',
                          )
                        : _copy(
                            'Sprawdź kod i zaloguj się na konto z zaproszonym adresem e-mail.',
                            'Check the code and sign in with the invited email address.',
                          ),
                  ),
                const SizedBox(height: 16),
                FilledButton(
                  key: const Key('garage_staff_invitation_submit'),
                  onPressed: _busy ? null : _submit,
                  child: Text(
                    widget.issue
                        ? _copy('Utwórz kod', 'Create code')
                        : _copy('Przyjmij zaproszenie', 'Accept invitation'),
                  ),
                ),
              ] else ...[
                Text(
                  _copy(
                    'Przekaż ten jednorazowy kod zaproszonej osobie przez bezpieczny kanał. Kod wygasa po 48 godzinach.',
                    'Share this one-time code securely with the invitee. It expires after 48 hours.',
                  ),
                ),
                const SizedBox(height: 12),
                SelectableText(
                  code,
                  key: const Key('garage_staff_issued_code'),
                ),
                OutlinedButton(
                  onPressed: () {
                    if (widget.isCurrentAccount())
                      Clipboard.setData(ClipboardData(text: code));
                  },
                  child: Text(_copy('Kopiuj kod', 'Copy code')),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
