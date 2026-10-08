import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/fleet_repository.dart';
import 'company_gate.dart';
import 'login_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _repository = FleetRepository();
  late final StreamSubscription<AuthState> _subscription;
  User? _user;

  @override
  void initState() {
    super.initState();
    _user = _repository.currentUser;
    _subscription = _repository.authChanges.listen((state) {
      if (!mounted) return;
      setState(() => _user = state.session?.user);
    });
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_user == null) return const LoginScreen();
    return CompanyGate(key: ValueKey(_user!.id));
  }
}
