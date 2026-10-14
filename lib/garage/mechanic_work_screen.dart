import 'package:flutter/material.dart';

import '../core/localization.dart';
import 'mechanic_board.dart';
import 'mechanic_jobs_repository.dart';
import 'media_repository.dart';
import 'order_media_screen.dart';

typedef GarageJobsLoader =
    Future<List<GarageMechanicAssignment>> Function();
typedef GarageEvidenceBuilder = Widget Function(String orderId);

/// Internal mechanic's assignment hub and private photo-evidence navigation.
///
/// Permissions come ONLY from garage_my_assigned_jobs (SECURITY INVOKER with
/// RLS). Media access remains independently RLS enforced by Supabase Storage.
/// No access to PDFs, estimates, customer PII or Fleet data is granted here.
/// Not yet exposed in production navigation or attached to hosted Garage DB.
class GarageMechanicWorkScreen extends StatefulWidget {
  const GarageMechanicWorkScreen({
    required this.loadJobs,
    required this.evidenceScreen,
    super.key,
  });

  factory GarageMechanicWorkScreen.forRepository({
    required GarageMechanicJobsRepository jobs,
    required GarageMediaRepository media,
    required String workspaceId,
    Key? key,
  }) {
    return GarageMechanicWorkScreen(
      key: key,
      loadJobs: () => jobs.fetchMyAssignments(workspaceId),
      evidenceScreen: (orderId) => GarageOrderMediaScreen.forRepository(
        repository: media,
        workspaceId: workspaceId,
        orderId: orderId,
        // No invoicing or PDF visibility for mechanics.
        showDocuments: false,
        canUploadPhotos: true,
        canUploadDocuments: false,
      ),
    );
  }

  final GarageJobsLoader loadJobs;
  final GarageEvidenceBuilder evidenceScreen;

  @override
  State<GarageMechanicWorkScreen> createState() =>
      _GarageMechanicWorkScreenState();
}

class _GarageMechanicWorkScreenState
    extends State<GarageMechanicWorkScreen> {
  bool _busy = true;
  List<GarageMechanicAssignment> _assignments = const [];
  String? _error;
  int _requestVersion = 0;

  bool get _pl => AppLocale.language.value == 'pl';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final request = ++_requestVersion;
    setState(() {
      _busy = true;
      _error = null;
      // Clear cached vehicle information on every refresh, including when
      // auth state or assignment permissions may have changed.
      _assignments = const [];
    });
    try {
      final assignments = await widget.loadJobs();
      if (!mounted || request != _requestVersion) return;
      setState(() => _assignments = List.unmodifiable(assignments));
    } catch (_) {
      if (!mounted || request != _requestVersion) return;
      setState(() {
        _assignments = const [];
        _error = _pl
            ? 'Nie udało się pobrać zleceń. Sprawdź dostęp i spróbuj ponownie.'
            : 'Could not load assigned jobs. Check access and retry.';
      });
    } finally {
      if (mounted && request == _requestVersion) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _open(String orderId) async {
    if (_busy ||
        !_assignments.any((assignment) => assignment.id == orderId)) {
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => widget.evidenceScreen(orderId),
      ),
    );
    if (mounted) {
      // On return, refetch permission-filtered jobs. Assignment may have
      // been revoked while the user was viewing the evidence.
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_pl ? 'Flotaryx Garage' : 'Flotaryx Garage'),
        actions: [
          IconButton(
            key: const Key('garage_mechanic_work_refresh'),
            tooltip: _pl ? 'Odśwież' : 'Refresh',
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _error!,
                          key: const Key('garage_mechanic_work_error'),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          key: const Key('garage_mechanic_work_retry'),
                          onPressed: _load,
                          child: Text(_pl ? 'Spróbuj ponownie' : 'Try again'),
                        ),
                      ],
                    ),
                  ),
                )
              : GarageMechanicBoard(
                  assignments: _assignments,
                  onOpenAssignment: _open,
                ),
    );
  }
}
