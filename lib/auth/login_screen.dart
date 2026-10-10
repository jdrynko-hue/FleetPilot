import 'package:flutter/material.dart';

import '../core/localization.dart';
import '../data/fleet_repository.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _repository = FleetRepository();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _registerMode = false;
  bool _busy = false;
  bool _obscurePassword = true;

  String get _language => AppLocale.language.value;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _busy = true);

    try {
      if (_registerMode) {
        final signedIn = await _repository.signUp(
          email: _email.text.trim(),
          password: _password.text,
          locale: _language,
        );
                if (!signedIn && mounted) {
          await showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Check your email'),
              content: Text(
                'We sent a confirmation link to ${_email.text.trim()}. Check your spam folder too.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
          if (mounted) setState(() => _registerMode = false);
        }
      } else {
        await _repository.signIn(
          email: _email.text.trim(),
          password: _password.text,
        );
      }
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _setLanguage(String value) {
    AppLocale.language.value = value;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            ClipRRect(
                               borderRadius: BorderRadius.circular(12),
                               child: Image.asset(
                                 'assets/branding/flotaryx_mark.png',
                                 width: 44,
                                 height: 44,
                               ),
                             ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Flotaryx',
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineMedium,
                              ),
                            ),
                            PopupMenuButton<String>(
                              tooltip: tr('language'),
                              initialValue: _language,
                              onSelected: _setLanguage,
                              itemBuilder: (_) => supportedLanguages
                                  .map(
                                    (code) => PopupMenuItem<String>(
                                      value: code,
                                      child: Text(languageLabel(code)),
                                    ),
                                  )
                                  .toList(),
                              icon: const Icon(Icons.language_rounded),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _registerMode
                              ? tr('create_account')
                              : tr('sign_in_subtitle'),
                        ),
                        const SizedBox(height: 24),
                        TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          autocorrect: false,
                          decoration: InputDecoration(
                            labelText: tr('email'),
                            prefixIcon: const Icon(Icons.email_outlined),
                          ),
                          validator: (value) {
                            final v = value?.trim() ?? '';

                            if (!v.contains('@') || !v.contains('.')) {
                              return tr('invalid_email');
                            }

                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _password,
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
                            labelText: tr('password'),
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                              ),
                            ),
                          ),
                          validator: (value) {
                            if ((value ?? '').length < 8) {
                              return tr('short_password');
                            }

                            return null;
                          },
                        ),
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: _busy ? null : _submit,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: _busy
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(
                                    _registerMode
                                        ? tr('create_account')
                                        : tr('sign_in'),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => setState(
                                  () => _registerMode = !_registerMode,
                                ),
                          child: Text(
                            _registerMode
                                ? tr('have_account')
                                : tr('no_account'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
