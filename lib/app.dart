import 'package:flutter/material.dart';

import 'auth/auth_gate.dart';
import 'core/app_config.dart';
import 'core/theme.dart';

class FleetPilotApp extends StatelessWidget {
  const FleetPilotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FleetPilot',
      debugShowCheckedModeBanner: false,
      theme: buildFleetPilotTheme(),
      home: AppConfig.isConfigured
          ? const AuthGate()
          : const _MissingConfigurationScreen(),
    );
  }
}

class _MissingConfigurationScreen extends StatelessWidget {
  const _MissingConfigurationScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('FleetPilot', style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 12),
                    const Text(
                      'Supabase is not configured. Start the app with SUPABASE_URL and '
                      'SUPABASE_PUBLISHABLE_KEY passed as --dart-define values.',
                    ),
                    const SizedBox(height: 16),
                    const SelectableText(
                      'flutter run -d chrome '
                      '--dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co '
                      '--dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
