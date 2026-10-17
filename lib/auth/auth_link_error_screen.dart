import 'package:flutter/material.dart';
import 'auth_ui_text.dart';
import 'forgot_password_screen.dart';

class AuthLinkErrorScreen extends StatelessWidget {
  const AuthLinkErrorScreen({super.key, required this.onContinue});

  final VoidCallback onContinue;

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
              const Icon(Icons.link_off, size: 40),
              const SizedBox(height: 16),
              Text(
                authText('Link expired or invalid', 'Link wygasł lub jest nieprawidłowy'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(authText('This sign-in or password reset link cannot be used. Request a new link or return to Flotaryx.',
                  'Ten link logowania lub zmiany hasła nie działa. Poproś o nowy link albo wróć do Flotaryx.')),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const ForgotPasswordScreen(),
                )),
                child: Text(authText('Request a new link', 'Poproś o nowy link')),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: onContinue,
                child: Text(authText('Return to Flotaryx', 'Wróć do Flotaryx')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
