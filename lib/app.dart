import 'package:flutter/material.dart';

import 'auth/auth_gate.dart';
import 'core/app_config.dart';
import 'core/localization.dart';
import 'core/theme.dart';

class FleetPilotApp extends StatelessWidget {
  const FleetPilotApp({super.key, this.recoveryLinkOnLaunch = false});

  final bool recoveryLinkOnLaunch;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: AppLocale.language,
      builder: (context, language, _) {
        return MaterialApp(
          key: ValueKey(language),
          title: 'Flotaryx',
          debugShowCheckedModeBanner: false,
          theme: buildFleetPilotTheme(),
          home: AppConfig.isConfigured
              ? AuthGate(recoveryLinkOnLaunch: recoveryLinkOnLaunch)
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
      body: Center(child: Text('Flotaryx configuration is missing.')),
    );
  }
}
