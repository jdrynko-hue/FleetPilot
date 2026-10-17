import 'package:flutter/material.dart';

import '../core/localization.dart';
import '../core/locale_preferences.dart';
import '../data/fleet_repository.dart';
import '../data/models.dart';
import '../shell/fleet_shell.dart';
import 'create_company_screen.dart';

typedef FleetInviteAcceptor = Future<void> Function(String code);
typedef FleetMembershipLoader = Future<List<CompanyMembership>> Function();

class CompanyGate extends StatefulWidget {
  const CompanyGate({
    super.key,
    this.inviteCode,
    this.acceptInvite,
    this.loadMemberships,
  });

  /// The production app reads its invite code from the URL.
  /// Overrides make edge cases testable without real user accounts.
  final String? inviteCode;
  final FleetInviteAcceptor? acceptInvite;
  final FleetMembershipLoader? loadMemberships;

  @override
  State<CompanyGate> createState() => _CompanyGateState();
}

class _CompanyGateState extends State<CompanyGate> {
  FleetRepository? _repository;
  late Future<List<CompanyMembership>> _future;
  bool _ignoreInvite = false;
  bool _inviteFailed = false;

  @override
  void initState() {
    super.initState();
    // A complete test override never touches the production Supabase client.
    if (widget.acceptInvite == null || widget.loadMemberships == null) {
      _repository = FleetRepository();
    }
    _reload();
  }

  void _reload() {
    _future = _bootstrap();
  }

  Future<List<CompanyMembership>> _bootstrap() async {
    final invite = widget.inviteCode ?? Uri.base.queryParameters['invite'];
    _inviteFailed = false;

    if (!_ignoreInvite && invite != null && invite.isNotEmpty) {
      try {
        if (widget.acceptInvite != null) {
          await widget.acceptInvite!(invite);
        } else {
          await _repository!.acceptCompanyInvite(invite);
        }
      } catch (_) {
        // An expired, mismatched or unverified invitation must never silently
        // send a new customer to "Create fleet" as if nothing happened.
        _inviteFailed = true;
      }
    }

    if (_repository != null) {
      try {
        final profile = await _repository!.fetchUserProfile();
        if (profile != null && supportedLanguages.contains(profile.locale)) {
          applyProfileLanguage(profile.locale);
        }
      } catch (_) {}
    }

    if (widget.loadMemberships != null) {
      return widget.loadMemberships!();
    }
    return _repository!.fetchMemberships();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<CompanyMembership>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      snapshot.error.toString(),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => setState(_reload),
                      child: Text(tr('try_again')),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        if (_inviteFailed) {
          final pl = AppLocale.language.value == 'pl';
          return Scaffold(
            body: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        pl ? 'Nie można przyjąć zaproszenia' : 'Unable to accept invitation',
                        key: const Key('fleet_invite_error_title'),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        pl
                            ? 'Link mógł wygasnąć lub dotyczyć innego adresu e-mail. Potwierdź swój adres e-mail albo poproś administratora floty o nowe zaproszenie.'
                            : 'The link may have expired or belong to a different email address. Verify your email or ask the fleet administrator for a new invitation.',
                      ),
                      const SizedBox(height: 20),
                      FilledButton(
                        key: const Key('retry_fleet_invite'),
                        onPressed: () => setState(_reload),
                        child: Text(tr('try_again')),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        key: const Key('continue_without_fleet_invite'),
                        onPressed: () {
                          setState(() {
                            _ignoreInvite = true;
                            _reload();
                          });
                        },
                        child: Text(pl ? 'Przejdź bez zaproszenia' : 'Continue without invitation'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        final memberships = snapshot.data ?? [];

        if (memberships.isEmpty) {
          return CreateCompanyScreen(onCreated: () => setState(_reload));
        }

        return FleetShell(memberships: memberships);
      },
    );
  }
}
