import 'package:flutter/material.dart';

import '../core/localization.dart';
import '../core/locale_preferences.dart';
import 'forgot_password_screen.dart';
import 'password_policy.dart';
import 'auth_ui_text.dart';
import 'portal_entry.dart';
import '../core/app_config.dart';
import '../data/fleet_repository.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.portal, this.onPortalChanged, this.onFindWorkshop});

  final PortalEntry? portal;
  final ValueChanged<PortalEntry>? onPortalChanged;
  final VoidCallback? onFindWorkshop;

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
          portal: widget.portal?.name,
        );
                if (!signedIn && mounted) {
          await showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(authText('Check your email', 'Sprawdź pocztę')),
              content: Text(
                authText('We sent a confirmation link to {email}. Check your spam folder too.',
                  'Na adres {email} wysłaliśmy link potwierdzający. Sprawdź również folder spam.')
                    .replaceAll('{email}', _email.text.trim()),
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
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_registerMode
          ? authText('Could not create the account. Try again later.',
              'Nie udało się utworzyć konta. Spróbuj później.')
          : authText('Could not sign in. Check your details and try again.',
              'Nie udało się zalogować. Sprawdź dane i spróbuj ponownie.'))));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _setLanguage(String value) {
    selectAppLanguage(value);
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
                        if (AppConfig.ecosystemQaEnabled)
                          PortalEntryPicker(selected: widget.portal,
                            onSelected: _busy ? null : widget.onPortalChanged,
                            onFindWorkshop: _busy ? null : widget.onFindWorkshop),
                        if (!AppConfig.ecosystemQaEnabled || _registerMode)
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
                            return validateAccountPassword(
                              value,
                              creatingNewPassword: _registerMode,
                              locale: _language,
                            );
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
                        if (!_registerMode)
                          TextButton(
                            key: const Key('forgot_password_button'),
                            onPressed: _busy
                                ? null
                                : () => Navigator.of(context).push<void>(
                                    MaterialPageRoute(
                                      builder: (_) => const ForgotPasswordScreen(),
                                    ),
                                  ),
                            child: Text(
                              authText('Forgot password?', 'Nie pamiętasz hasła?'),
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
