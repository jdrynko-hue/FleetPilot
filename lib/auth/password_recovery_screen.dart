import 'package:flutter/material.dart';
import '../data/fleet_repository.dart';
import '../core/localization.dart';
import 'password_policy.dart';
import 'auth_ui_text.dart';

typedef PasswordUpdater = Future<void> Function(String password);
typedef PasswordRecoveryCompleted = Future<void> Function();

/// Only shown after Supabase emits AuthChangeEvent.passwordRecovery.
/// Updating the password uses the authenticated recovery session.
class PasswordRecoveryScreen extends StatefulWidget {
  const PasswordRecoveryScreen({
    super.key,
    this.updatePassword,
    this.onCompleted,
  });

  final PasswordUpdater? updatePassword;
  final PasswordRecoveryCompleted? onCompleted;

  @override
  State<PasswordRecoveryScreen> createState() => _PasswordRecoveryScreenState();
}

class _PasswordRecoveryScreenState extends State<PasswordRecoveryScreen> {
  final _key = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _busy = false;
  String _loc(String en, String pl) =>
      authText(en, pl);
  bool _completed = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_key.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.updatePassword != null) {
        await widget.updatePassword!(_password.text);
      } else {
        await FleetRepository().setNewPassword(_password.text);
      }
      if (!mounted) return;
      setState(() => _completed = true);
      if (widget.onCompleted != null) await widget.onCompleted!();
    } catch (_) {
      if (mounted) setState(() => _error = _loc('Could not update password. Request a new link if it has expired.', 'Nie udało się zmienić hasła. Jeśli link wygasł, poproś o nowy.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              Text(_loc('Choose a new password', 'Ustaw nowe hasło'),
                style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 12),
              if (_completed)
                Text(
                  _loc('Your password was updated. Please sign in again.', 'Hasło zostało zmienione. Zaloguj się ponownie.'),
                  key: Key('password_recovery_completed'),
                )
              else
                Form(
                  key: _key,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        key: const Key('new_password'),
                        controller: _password,
                        obscureText: true,
                        autofillHints: const [AutofillHints.newPassword],
                        decoration: InputDecoration(
                          labelText: _loc('New password', 'Nowe hasło'),
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          return validateAccountPassword(
                            value,
                            creatingNewPassword: true,
                            locale: AppLocale.language.value,
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        key: const Key('confirm_password'),
                        controller: _confirmation,
                        obscureText: true,
                        autofillHints: const [AutofillHints.newPassword],
                        decoration: InputDecoration(
                          labelText: _loc('Confirm new password', 'Potwierdź nowe hasło'),
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value != _password.text) return _loc('Passwords do not match.', 'Hasła są różne.');
                          return null;
                        },
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          key: const Key('password_recovery_error'),
                          style: TextStyle(color: Theme.of(context).colorScheme.error),
                        ),
                      ],
                      const SizedBox(height: 18),
                      FilledButton(
                        key: const Key('set_password_button'),
                        onPressed: _busy ? null : _save,
                        child: Text(_busy ? _loc('Updating…', 'Zapisywanie…') : _loc('Update password', 'Zapisz nowe hasło')),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
