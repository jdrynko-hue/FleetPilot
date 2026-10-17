import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/app_config.dart';
import 'core/locale_preferences.dart';
import 'auth/auth_redirect_error.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  initializeAppLanguage(uri: Uri.base,
    device: WidgetsBinding.instance.platformDispatcher.locale.toLanguageTag());
  final authLinkErrorOnLaunch = hasAuthRedirectError(Uri.base);

  // Save the recovery marker before the auth SDK consumes the redirect URL.
  final recoveryLinkOnLaunch =
      !authLinkErrorOnLaunch &&
      (Uri.base.fragment.contains('type=recovery') ||
          Uri.base.queryParameters['type'] == 'recovery');

  if (AppConfig.isConfigured) {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabasePublishableKey,
      // A failed callback contains no usable session. Skip SDK deep-link
      // parsing for this launch to avoid an unhandled Auth stream error.
      authOptions: FlutterAuthClientOptions(
        detectSessionInUri: !authLinkErrorOnLaunch,
      ),
    );
  }

  runApp(FleetPilotApp(
    recoveryLinkOnLaunch: recoveryLinkOnLaunch,
    authLinkErrorOnLaunch: authLinkErrorOnLaunch,
  ));
}
