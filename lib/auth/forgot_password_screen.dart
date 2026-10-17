import 'package:flutter/material.dart';
import '../data/fleet_repository.dart';
import 'auth_ui_text.dart';

typedef PasswordResetRequester = Future<void> Function(String email);

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.requestReset});

  final PasswordResetRequester? requestReset;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _busy = false;
  String _loc(String en, String pl) =>
      authText(en, pl);
  bool _submitted = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      if (widget.requestReset != null) {
        await widget.requestReset!(_email.text.trim());
      } else {
        await FleetRepository().sendPasswordReset(_email.text.trim());
      }
      if (mounted) setState(() => _submitted = true);
    } catch (_) {
      if (mounted) {
        setState(() => _error = _loc('Could not process the request. Try again later.', 'Nie udało się wysłać wiadomości. Spróbuj później.'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_loc('Reset password', 'Resetowanie hasła'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ListView(
            padding: const EdgeInsets.all(24),
            shrinkWrap: true,
            children: [
              Text(
                _loc('Password recovery', 'Odzyskiwanie hasła'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              if (_submitted)
                Text(
                  _loc('If an account exists for this email, a password reset link has been sent. Check your inbox and spam folder.', 'Jeśli konto o tym adresie istnieje, wysłaliśmy link do zmiany hasła. Sprawdź skrzynkę i spam.'),
                  key: Key('reset_request_confirmation'),
                )
              else
                Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(_loc('Enter the email address for your Flotaryx account.', 'Podaj adres e-mail konta Flotaryx.')),
                      const SizedBox(height: 12),
                      TextFormField(
                        key: const Key('reset_email'),
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        autocorrect: false,
                        decoration: InputDecoration(
                          labelText: _loc('Email', 'E-mail'),
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          final email = (value ?? '').trim();
                          if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
                            return _loc('Enter a valid email address.', 'Podaj prawidłowy adres e-mail.');
                          }
                          return null;
                        },
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          key: const Key('reset_request_error'),
                          style: TextStyle(color: Theme.of(context).colorScheme.error),
                        ),
                      ],
                      const SizedBox(height: 18),
                      FilledButton(
                        key: const Key('request_reset_button'),
                        onPressed: _busy ? null : _send,
                        child: Text(_busy ? _loc('Sending…', 'Wysyłanie…') : _loc('Send reset link', 'Wyślij link do zmiany hasła')),
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
