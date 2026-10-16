import 'package:flutter/material.dart';

import 'auth/auth_gate.dart';
import 'core/app_config.dart';
import 'core/localization.dart';
import 'core/material_localization.dart';
import 'core/theme.dart';

class FleetPilotApp extends StatelessWidget {
  const FleetPilotApp({
    super.key,
    this.recoveryLinkOnLaunch = false,
    this.authLinkErrorOnLaunch = false,
  });

  final bool recoveryLinkOnLaunch;
  final bool authLinkErrorOnLaunch;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: AppLocale.language,
      builder: (context, language, _) {
        return MaterialApp(
          key: ValueKey(language),
          title: 'Flotaryx',
          locale: materialLocale(language),
          supportedLocales: supportedMaterialLocales,
          localizationsDelegates: materialLocalizationDelegates,
          debugShowCheckedModeBanner: false,
          theme: buildFleetPilotTheme(),
          home: AppConfig.isConfigured
              ? AuthGate(
                  recoveryLinkOnLaunch: recoveryLinkOnLaunch,
                  authLinkErrorOnLaunch: authLinkErrorOnLaunch,
                )
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
