import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/app_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Save the recovery marker before the auth SDK consumes the redirect URL.
  final recoveryLinkOnLaunch =
      Uri.base.fragment.contains('type=recovery') ||
      Uri.base.queryParameters['type'] == 'recovery';

  if (AppConfig.isConfigured) {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabasePublishableKey,
    );
  }

  runApp(FleetPilotApp(recoveryLinkOnLaunch: recoveryLinkOnLaunch));
}
