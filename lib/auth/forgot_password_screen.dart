import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
        await Supabase.instance.client.auth.resetPasswordForEmail(
          _email.text.trim(),
          redirectTo: 'https://flotaryx.com/app/',
        );
      }
      if (mounted) setState(() => _submitted = true);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not process the request. Try again later.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reset password')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ListView(
            padding: const EdgeInsets.all(24),
            shrinkWrap: true,
            children: [
              Text(
                'Password recovery',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              if (_submitted)
                const Text(
                  'If an account exists for this email, a password reset link has been sent. Check your inbox and spam folder.',
                  key: Key('reset_request_confirmation'),
                )
              else
                Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('Enter the email address for your Flotaryx account.'),
                      const SizedBox(height: 12),
                      TextFormField(
                        key: const Key('reset_email'),
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          final email = (value ?? '').trim();
                          if (!RegExp(r'^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$').hasMatch(email)) {
                            return 'Enter a valid email address.';
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
                        child: Text(_busy ? 'Sending…' : 'Send reset link'),
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
