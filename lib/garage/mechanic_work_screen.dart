import 'package:flutter/material.dart';

import 'garage_ui_text.dart';
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
    this.accessNotice,
    super.key,
  });

  factory GarageMechanicWorkScreen.forRepository({
    required GarageMechanicJobsRepository jobs,
    required GarageMediaRepository media,
    required String workspaceId,
    Widget? accessNotice,
    Key? key,
  }) {
    return GarageMechanicWorkScreen(
      key: key,
      accessNotice: accessNotice,
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
  final Widget? accessNotice;

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
  int _scope = 0;
  MaterialPageRoute<void>? _evidenceRoute;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant GarageMechanicWorkScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.loadJobs != widget.loadJobs ||
        oldWidget.evidenceScreen != widget.evidenceScreen) {
      _scope++;
      _dismissEvidenceRoute();
      _load();
    }
  }

  @override
  void dispose() {
    _scope++;
    _requestVersion++;
    _dismissEvidenceRoute();
    super.dispose();
  }

  void _dismissEvidenceRoute() {
    final route = _evidenceRoute;
    final navigator = route?.navigator;
    _evidenceRoute = null;
    if (route == null || navigator == null) return;
    // Scope changes can happen during a parent build. Remove only our route
    // after that frame, including when another dialog is above it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (navigator.mounted && route.isActive) navigator.removeRoute(route);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
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
        _error = GarageUiText.get('mechanicLoadFailed');
      });
    } finally {
      if (mounted && request == _requestVersion) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _open(String orderId, int scope, int listVersion) async {
    if (!mounted || scope != _scope || listVersion != _requestVersion ||
        _busy || _evidenceRoute != null ||
        !_assignments.any((assignment) => assignment.id == orderId)) {
      return;
    }
    final evidence = widget.evidenceScreen;
    final route = MaterialPageRoute<void>(
      builder: (_) => mounted && scope == _scope
          ? evidence(orderId)
          : const SizedBox.shrink(),
    );
    _evidenceRoute = route;
    try {
      await Navigator.of(context).push<void>(route);
    } finally {
      if (identical(_evidenceRoute, route)) _evidenceRoute = null;
      if (mounted && scope == _scope) {
        // Assignment may have been revoked while evidence was open.
        await _load();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = _scope;
    final listVersion = _requestVersion;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Flotaryx Garage'),
        actions: [
          IconButton(
            key: const Key('garage_mechanic_work_refresh'),
            tooltip: GarageUiText.get('refresh'),
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(children: [
        if (widget.accessNotice != null) widget.accessNotice!,
        Expanded(child: _busy
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
                          child: Text(GarageUiText.get('retry')),
                        ),
                      ],
                    ),
                  ),
                )
              : GarageMechanicBoard(
                  assignments: _assignments,
                  onOpenAssignment: (id) => _open(id, scope, listVersion),
                )),
      ]),
    );
  }
}
