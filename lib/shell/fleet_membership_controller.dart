import 'package:flutter/foundation.dart';

import '../data/models.dart';

/// Keeps the fleet selector and visible permissions on one authorized snapshot.
class FleetMembershipController extends ChangeNotifier {
  FleetMembershipController({
    required List<CompanyMembership> memberships,
    required String selectedId,
    required this.load,
    required this.currentAccountId,
  }) : _memberships = List.unmodifiable(memberships),
       _selectedId = selectedId,
       _accountId = currentAccountId();

  final Future<List<CompanyMembership>> Function() load;
  final String? Function() currentAccountId;
  final String? _accountId;
  List<CompanyMembership> _memberships;
  String _selectedId;
  int _request = 0;
  bool _disposed = false;
  bool loading = false;
  bool failed = false;

  List<CompanyMembership> get memberships => _memberships;
  CompanyMembership? get selected {
    for (final member in _memberships) {
      if (member.companyId == _selectedId) return member;
    }
    return _memberships.isEmpty ? null : _memberships.first;
  }

  void select(String id) {
    if (_disposed || loading || currentAccountId() != _accountId ||
        !_memberships.any((member) => member.companyId == id)) return;
    _selectedId = id;
    notifyListeners();
  }

  Future<void> refresh() async {
    if (_disposed || currentAccountId() != _accountId) return;
    final request = ++_request;
    loading = true;
    failed = false;
    notifyListeners();
    bool current() => !_disposed && request == _request &&
        currentAccountId() == _accountId;
    try {
      final members = await load();
      if (!current()) return;
      _memberships = List.unmodifiable(members);
      _selectedId = selected?.companyId ?? '';
    } catch (_) {
      if (!current()) return;
      // A failed access check cannot keep previously granted controls visible.
      _memberships = const [];
      failed = true;
    } finally {
      if (current()) {
        loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _request++;
    super.dispose();
  }
}
