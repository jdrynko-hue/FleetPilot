import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/formatters.dart';
import '../core/widgets.dart';
import '../data/fleet_repository.dart';
import '../data/models.dart';
import 'issue_form_screen.dart';

class IssuesScreen extends StatefulWidget {
  const IssuesScreen({
    required this.company,
    required this.canManage,
    required this.refreshToken,
    required this.onDataChanged,
    super.key,
  });

  final CompanyMembership company;
  final bool canManage;
  final int refreshToken;
  final VoidCallback onDataChanged;

  @override
  State<IssuesScreen> createState() => _IssuesScreenState();
}

class _IssuesScreenState extends State<IssuesScreen> {
  final _repository = FleetRepository();
  late Future<List<FleetIssue>> _future;
  String? _status;
  String? _priority;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant IssuesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken ||
        oldWidget.company.companyId != widget.company.companyId)
      _load();
  }

  void _load() => _future = _repository.fetchIssues(widget.company.companyId);

  Future<void> _open({FleetIssue? issue}) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => IssueFormScreen(company: widget.company, issue: issue),
      ),
    );
    if (changed == true) {
      setState(_load);
      widget.onDataChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<FleetIssue>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done)
          return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError)
          return ErrorState(
            error: snapshot.error!,
            onRetry: () => setState(_load),
          );
        final all = snapshot.data ?? [];
        final issues = all
            .where(
              (i) =>
                  (_status == null || i.status == _status) &&
                  (_priority == null || i.priority == _priority),
            )
            .toList();
        return Scaffold(
          backgroundColor: Colors.transparent,
          floatingActionButton: widget.canManage
              ? FloatingActionButton.extended(
                  onPressed: () => _open(),
                  icon: const Icon(Icons.add),
                  label: const Text('Add issue'),
                )
              : null,
          body: RefreshIndicator(
            onRefresh: () async => setState(_load),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Issues',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: 220,
                      child: DropdownButtonFormField<String?>(
                        initialValue: _status,
                        decoration: const InputDecoration(labelText: 'Status'),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('All statuses'),
                          ),
                          ...issueStatuses.map(
                            (s) => DropdownMenuItem<String?>(
                              value: s,
                              child: Text(prettifyEnum(s)),
                            ),
                          ),
                        ],
                        onChanged: (value) => setState(() => _status = value),
                      ),
                    ),
                    SizedBox(
                      width: 220,
                      child: DropdownButtonFormField<String?>(
                        initialValue: _priority,
                        decoration: const InputDecoration(
                          labelText: 'Priority',
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('All priorities'),
                          ),
                          ...issuePriorities.map(
                            (s) => DropdownMenuItem<String?>(
                              value: s,
                              child: Text(prettifyEnum(s)),
                            ),
                          ),
                        ],
                        onChanged: (value) => setState(() => _priority = value),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (issues.isEmpty)
                  const SizedBox(
                    height: 360,
                    child: EmptyState(
                      icon: Icons.report_problem_outlined,
                      title: 'No issues',
                      message:
                          'Defects and operational issues will appear here.',
                    ),
                  )
                else
                  Card(
                    child: Column(
                      children: [
                        for (var i = 0; i < issues.length; i++) ...[
                          ListTile(
                            onTap: widget.canManage
                                ? () => _open(issue: issues[i])
                                : null,
                            leading: const CircleAvatar(
                              child: Icon(Icons.report_problem_outlined),
                            ),
                            title: Text(
                              '${issues[i].registration ?? 'Vehicle'} — ${issues[i].title}',
                            ),
                            subtitle: Text(
                              '${prettifyEnum(issues[i].priority)} • ${formatDateTime(issues[i].reportedAt)}',
                            ),
                            trailing: StatusPill(
                              label: prettifyEnum(issues[i].status),
                            ),
                          ),
                          if (i != issues.length - 1) const Divider(height: 1),
                        ],
                      ],
                    ),
                  ),
                const SizedBox(height: 84),
              ],
            ),
          ),
        );
      },
    );
  }
}
