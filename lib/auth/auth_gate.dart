import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/fleet_repository.dart';
import '../core/app_config.dart';
import '../ecosystem/ecosystem_gate.dart';
import 'company_gate.dart';
import 'login_screen.dart';
import 'portal_entry.dart';
import '../garage/consumer_booking_screen.dart';
import '../garage/consumer_booking_repository.dart';
import 'password_recovery_screen.dart';
import 'auth_link_error_screen.dart';
import 'auth_redirect_error.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    this.recoveryLinkOnLaunch = false,
    this.authLinkErrorOnLaunch = false,
  });

  final bool recoveryLinkOnLaunch;
  final bool authLinkErrorOnLaunch;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _repository = FleetRepository();
  late final StreamSubscription<AuthState> _subscription;
  User? _user;
  bool _passwordRecovery = false;
  bool _authLinkError = false;
  PortalEntry? _portal;

  @override
  void initState() {
    super.initState();
    _user = _repository.currentUser;
    _portal = portalEntryFromUri(Uri.base);
    _authLinkError = widget.authLinkErrorOnLaunch || hasAuthRedirectError(Uri.base);
    // The redirect may be consumed during Supabase.initialize, before the
    // listener is attached. Preserve the explicit URL recovery marker.
    _passwordRecovery =
        !_authLinkError &&
        (widget.recoveryLinkOnLaunch ||
            Uri.base.fragment.contains('type=recovery') ||
            Uri.base.queryParameters['type'] == 'recovery');
    if (AppConfig.ecosystemQaEnabled && Uri.base.queryParameters['portal'] == 'search') {
      WidgetsBinding.instance.addPostFrameCallback((_) => _findWorkshop());
    }
    _subscription = _repository.authChanges.listen((state) {
      if (!mounted) return;
      if (_user?.id != state.session?.user.id) {
        // Pushed private routes must not survive logout or an account switch.
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
      setState(() {
        _user = state.session?.user;
        if (state.event == AuthChangeEvent.passwordRecovery) {
          _passwordRecovery = true;
        }
      });
    });
  }

  void _findWorkshop() {
    if (!mounted || _user != null || _authLinkError || _passwordRecovery) return;
    final repository = GarageBookingRepository(Supabase.instance.client);
    Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) =>
      GarageBookingSearchScreen(search: repository.findWorkshops,
        submit: repository.request,
        beforeRequest: () async {
          Navigator.of(context).pop();
          if (mounted) setState(() => _portal = PortalEntry.customer);
          return false;
        })));
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_authLinkError) {
      return AuthLinkErrorScreen(
        onContinue: () => setState(() => _authLinkError = false),
      );
    }
    // Password-recovery sessions must never enter the fleet dashboard until
    // the password has been changed. Sign out after the successful update.
    if (_passwordRecovery && _user != null) {
      return PasswordRecoveryScreen(
        onCompleted: () async {
          await _repository.signOut();
          if (mounted) {
            setState(() {
              _passwordRecovery = false;
              _user = null;
            });
          }
        },
      );
    }
    if (_user == null) return LoginScreen(
      portal: _portal,
      onPortalChanged: (entry) => setState(() => _portal = entry),
      onFindWorkshop: AppConfig.ecosystemQaEnabled ? _findWorkshop : null,
    );
    // Fleet invitation handling keeps priority, including its explicit errors.
    final invite = Uri.base.queryParameters['invite'];
    if (AppConfig.ecosystemQaEnabled && (invite == null || invite.isEmpty)) {
      return EcosystemGate.forClient(
        Supabase.instance.client, preferredPortal: _portal, key: ValueKey(_user!.id));
    }
    return CompanyGate(key: ValueKey(_user!.id));
  }
}
