import 'package:flutter/material.dart';

import 'auth/auth_gate.dart';
import 'core/app_config.dart';
import 'core/localization.dart';
import 'core/theme.dart';

class FleetPilotApp extends StatelessWidget {
  const FleetPilotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: AppLocale.language,
      builder: (context, language, _) {
        return MaterialApp(
          key: ValueKey(language),
          title: 'FleetPilot',
          debugShowCheckedModeBanner: false,
          theme: buildFleetPilotTheme(),
          home: AppConfig.isConfigured
              ? const AuthGate()
              : const _MissingConfigurationScreen(),
        );
      },
    );
  }
}

class _MissingConfigurationScreen extends StatelessWidget {
  const _MissingConfigurationScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('FleetPilot configuration is missing.')),
    );
  }
}
