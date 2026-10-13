import 'package:flutter/material.dart';
import '../core/localization.dart';
import 'forgot_password_screen.dart';

class AuthLinkErrorScreen extends StatelessWidget {
  const AuthLinkErrorScreen({super.key, required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final polish = AppLocale.language.value == 'pl';
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
                polish ? 'Link wygasł lub jest nieprawidłowy' : 'Link expired or invalid',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(polish
                  ? 'Ten link logowania lub zmiany hasła nie działa. Poproś o nowy link albo wróć do Flotaryx.'
                  : 'This sign-in or password reset link cannot be used. Request a new link or return to Flotaryx.'),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const ForgotPasswordScreen(),
                )),
                child: Text(polish ? 'Poproś o nowy link' : 'Request a new link'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: onContinue,
                child: Text(polish ? 'Wróć do Flotaryx' : 'Return to Flotaryx'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
