import 'package:flutter/material.dart';

import 'records_view.dart';

/// Reports & Exports — the mobile port of the SCP's Reports tab.
///
/// One page, the same one `scp/reports.php` renders: the four export types
/// (Tickets, Tasks, Users, Organizations) with their counts, each type's own
/// filters, a column picker, and a single Download CSV.
///
/// The dashboard's tabular statistics are deliberately not here. On the web
/// they live on `scp/dashboard.php`, not on the Reports page, and the mobile
/// Dashboard already carries the same ground in its own shape — the activity
/// chart plus the by-priority / by-department / by-agent breakdowns from
/// `GET /reports/summary`.
///
/// Reached from Menu → Workspace → Reports, which — like the web's `reports`
/// tab — is gated on `reports.export` (see `Me.canViewReports`). Every route
/// behind it re-checks that permission server-side, accepting it either
/// globally or from any department role, exactly as `scp/reports.php` does.
class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reports & Exports')),
      body: const SafeArea(child: RecordsExportView()),
    );
  }
}
