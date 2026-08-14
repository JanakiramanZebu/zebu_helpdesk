import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../data/tasks_repository.dart';
import '../../data/tickets_repository.dart';
import '../../models/task.dart';
import '../../models/ticket.dart';
import '../../models/saved_queue.dart';
import '../../providers.dart';
import '../../widgets/paged_list_view.dart';
import '../../widgets/skeleton.dart';
import '../tasks/widgets/task_row.dart';
import '../tickets/widgets/ticket_row.dart';

/// The tickets/tasks that belong to a saved [queue] — opened by tapping a queue
/// on the Saved Queues screen.
///
/// Ticket queues are resolved **server-side** via `GET /tickets?queue={id}` (the
/// backend rebuilds the queue's query). `/tasks` has no `queue` param, so task
/// queues instead replay the queue's stored [SavedQueue.criteria] as flattened
/// query params ([SavedQueue.toQuery]) — best-effort, since unknown params are
/// ignored server-side.
class QueueResultsScreen extends ConsumerWidget {
  const QueueResultsScreen({super.key, required this.queue});

  final SavedQueue queue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(queue.fullName)),
      body: SafeArea(
        child: queue.type == 'task'
            ? _taskList(context, ref)
            : _ticketList(context, ref),
      ),
    );
  }

  Widget _ticketList(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(ticketsRepositoryProvider);
    return PagedListView<Ticket>(
      skeleton: const ListSkeleton(),
      emptyMessage: 'No tickets',
      emptyHint: 'This queue has no matching tickets.',
      fetch: (page) => repo.list(TicketQuery(queue: queue.id, page: page)),
      itemBuilder: (context, t) => TicketRow(
        ticket: t,
        onTap: () => context.push(Routes.ticket(t.id)),
      ),
    );
  }

  Widget _taskList(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(tasksRepositoryProvider);
    return PagedListView<Task>(
      skeleton: const ListSkeleton(),
      emptyMessage: 'No tasks',
      emptyHint: 'This queue has no matching tasks.',
      fetch: (page) =>
          repo.list(TaskQuery(extra: queue.toQuery(), page: page)),
      // Pass the row task so the detail can borrow the due date the detail
      // endpoint omits (see TaskDetailScreen.seed).
      itemBuilder: (context, t) => TaskRow(
        task: t,
        onTap: () => context.push(Routes.task(t.id), extra: t),
      ),
    );
  }
}
