import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/fleet_repository.dart';
import 'company_gate.dart';
import 'login_screen.dart';
import 'password_recovery_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _repository = FleetRepository();
  late final StreamSubscription<AuthState> _subscription;
  User? _user;
  bool _passwordRecovery = false;

  @override
  void initState() {
    super.initState();
    _user = _repository.currentUser;
    _subscription = _repository.authChanges.listen((state) {
      if (!mounted) return;
      setState(() {
        _user = state.session?.user;
        if (state.event == AuthChangeEvent.passwordRecovery) {
          _passwordRecovery = true;
        }
      });
    });
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Password-recovery sessions must never enter the fleet dashboard until
    // the password has been changed. Sign out after the successful update.
    if (_passwordRecovery) {
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
    if (_user == null) return const LoginScreen();
    return CompanyGate(key: ValueKey(_user!.id));
  }
}
