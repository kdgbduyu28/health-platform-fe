import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../app/adaptive_layout.dart';
import '../app/clinic_router.dart';
import '../models/app_role.dart';
import '../models/appointment.dart';
import '../models/appointment_status.dart';
import '../providers/clinic_provider.dart';
import '../providers/clinical_provider.dart';
import '../providers/preferences_provider.dart';
import '../theme/tone.dart';
import 'complete_visit_sheet.dart';
import 'status_actions.dart';
import 'status_badge.dart';

/// The columns of [AppointmentBoard], left to right as a visit moves through
/// the day. Cancelled visits and no-shows are in none of them: they sit
/// folded away under [completed].
enum BoardColumn {
  upcoming('Upcoming', AppointmentStatus.pending),
  planned('Planned', AppointmentStatus.confirmed),
  inProgress('In progress', AppointmentStatus.inConsultation),
  completed('Completed', AppointmentStatus.completed);

  const BoardColumn(this.label, this._tone);

  final String label;
  final AppointmentStatus _tone;

  Color get color => _tone.color;
  IconData get icon => _tone.icon;

  static BoardColumn? of(AppointmentStatus s) => switch (s) {
        AppointmentStatus.pending => upcoming,
        AppointmentStatus.confirmed => planned,
        AppointmentStatus.arrived ||
        AppointmentStatus.inConsultation =>
          inProgress,
        AppointmentStatus.completed => completed,
        AppointmentStatus.cancelled || AppointmentStatus.noShow => null,
      };
}

/// The one move forward a visit can make from where it stands, for whoever
/// is looking — the board's button, and what dragging a card does.
typedef BoardStep = ({
  AppointmentStatus to,
  String label,
  IconData icon,
  String done,
});

/// What [app] can do next with [a]. [clinician] is whether the signed-in
/// membership may start consultations (doctors and admins).
///
/// Mirrors the flow the database enforces (20260930120000): the front desk
/// confirms, checks in and marks a visit done; only clinicians start a
/// consultation. Marking done opens [showCompleteVisitSheet]. From
/// "Planned", the doctor app starts the consultation itself — a doctor
/// dragging a card into "In progress" is seeing that patient — while the
/// desk and admin apps check the patient in to the waiting room.
BoardStep? boardNextStep(
  Appointment a, {
  required AppRole app,
  required bool clinician,
}) {
  final who = a.patient.name;
  return switch (a.status) {
    AppointmentStatus.pending => (
        to: AppointmentStatus.confirmed,
        label: 'Confirm',
        icon: Icons.check,
        done: 'Appointment confirmed',
      ),
    AppointmentStatus.confirmed when app == AppRole.doctor => (
        to: AppointmentStatus.inConsultation,
        label: 'Start',
        icon: Icons.play_arrow,
        done: 'Consultation with $who started',
      ),
    AppointmentStatus.confirmed => (
        to: AppointmentStatus.arrived,
        label: 'Check in',
        icon: Icons.how_to_reg,
        done: '$who is in the waiting room',
      ),
    AppointmentStatus.arrived when clinician => (
        to: AppointmentStatus.inConsultation,
        label: 'Start',
        icon: Icons.play_arrow,
        done: 'Consultation with $who started',
      ),
    AppointmentStatus.arrived || AppointmentStatus.inConsultation => (
        to: AppointmentStatus.completed,
        label: 'Mark done',
        icon: Icons.task_alt,
        done: 'Visit done',
      ),
    _ => null,
  };
}

/// Switches a screen between the list and [AppointmentBoard]. Remembered per
/// app on this device.
class AppointmentViewToggle extends ConsumerWidget {
  const AppointmentViewToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(appointmentViewProvider);
    final board = view == AppointmentView.board;
    return IconButton(
      icon: Icon(board ? Icons.view_agenda_outlined : Icons.view_kanban_outlined),
      tooltip: board ? 'Show as a list' : 'Show as a board',
      onPressed: () => ref
          .read(appointmentViewProvider.notifier)
          .set(board ? AppointmentView.list : AppointmentView.board),
    );
  }
}

/// A day's visits in columns by where each one stands: Upcoming (booked, to
/// confirm), Planned (confirmed), In progress (in the waiting room or with
/// the doctor) and Completed.
///
/// On a wide screen the columns sit side by side and a card can be dragged
/// (press and hold, then move) one column to the right — only where its
/// [boardNextStep] leads, so the board never offers a move the database
/// would refuse. On a narrow screen the columns become tabs, and each card's
/// button does the same.
///
/// Visits are shown as given: the caller picks the day and whose visits.
class AppointmentBoard extends ConsumerWidget {
  const AppointmentBoard({
    super.key,
    required this.appointments,
    this.showDoctor = true,
    this.onOpen,
  });

  final List<Appointment> appointments;

  /// Whether cards name the doctor. Off in the doctor app: they are all theirs.
  final bool showDoctor;

  /// What tapping a card does. By default it opens the visit's page.
  final void Function(Appointment)? onOpen;

  /// Below this, four columns get too narrow to read; the board becomes tabs.
  static const double minWideWidth = 880;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appRoleProvider);
    final clinician = ref.watch(canSeeClinicalNotesProvider).value ??
        app == AppRole.doctor;
    BoardStep? stepOf(Appointment a) =>
        boardNextStep(a, app: app, clinician: clinician);

    final lanes = {for (final c in BoardColumn.values) c: <Appointment>[]};
    final closed = <Appointment>[];
    for (final a in appointments) {
      final column = BoardColumn.of(a.status);
      (column == null ? closed : lanes[column]!).add(a);
    }
    for (final list in [...lanes.values, closed]) {
      list.sort((a, b) => a.dateTime.compareTo(b.dateTime));
    }
    // With the doctor first, then the waiting room in order of arrival: the
    // top card is the one to deal with next.
    lanes[BoardColumn.inProgress]!.sort((a, b) {
      final withDoctor = (a.status == AppointmentStatus.inConsultation ? 0 : 1)
          .compareTo(b.status == AppointmentStatus.inConsultation ? 0 : 1);
      if (withDoctor != 0) return withDoctor;
      return (a.arrivedAt ?? a.dateTime).compareTo(b.arrivedAt ?? b.dateTime);
    });

    void open(Appointment a) => onOpen != null
        ? onOpen!(a)
        : context.pushInClinic('/appointments/${a.id}');

    Future<void> advance(Appointment a) async {
      final step = stepOf(a);
      if (step == null) return;
      if (step.to == AppointmentStatus.completed) {
        await showCompleteVisitSheet(context, ref, a);
        return;
      }
      await changeAppointmentStatus(context, ref, a, step.to, done: step.done);
    }

    Widget lane(BoardColumn column, {required bool draggable}) => _Lane(
          column: column,
          appointments: lanes[column]!,
          closed: column == BoardColumn.completed ? closed : const [],
          showDoctor: showDoctor,
          draggable: draggable,
          stepOf: stepOf,
          onOpen: open,
          onAdvance: advance,
        );

    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxWidth < minWideWidth) {
          return _BoardTabs(
            counts: {for (final c in BoardColumn.values) c: lanes[c]!.length},
            // Open on what needs attention now.
            initial: lanes[BoardColumn.inProgress]!.isNotEmpty
                ? BoardColumn.inProgress
                : BoardColumn.planned,
            lane: (c) => lane(c, draggable: false),
          );
        }
        return Centered(
          maxWidth: ContentWidth.wide + 32,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, c) in BoardColumn.values.indexed) ...[
                  if (i > 0) const SizedBox(width: 12),
                  Expanded(child: lane(c, draggable: true)),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BoardTabs extends StatelessWidget {
  const _BoardTabs({
    required this.counts,
    required this.initial,
    required this.lane,
  });

  final Map<BoardColumn, int> counts;
  final BoardColumn initial;
  final Widget Function(BoardColumn) lane;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: BoardColumn.values.length,
      initialIndex: initial.index,
      child: Column(
        children: [
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              for (final c in BoardColumn.values)
                Tab(text: '${c.label} (${counts[c]})'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                for (final c in BoardColumn.values)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: lane(c),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One column: its heading and count, its cards, and — for a card being
/// dragged whose next step lands here — a highlight to drop it on.
class _Lane extends StatelessWidget {
  const _Lane({
    required this.column,
    required this.appointments,
    required this.closed,
    required this.showDoctor,
    required this.draggable,
    required this.stepOf,
    required this.onOpen,
    required this.onAdvance,
  });

  final BoardColumn column;
  final List<Appointment> appointments;

  /// Cancelled visits and no-shows, folded away at the bottom.
  final List<Appointment> closed;
  final bool showDoctor;
  final bool draggable;
  final BoardStep? Function(Appointment) stepOf;
  final void Function(Appointment) onOpen;
  final Future<void> Function(Appointment) onAdvance;

  bool _lands(Appointment a) {
    final step = stepOf(a);
    return step != null &&
        BoardColumn.of(step.to) == column &&
        BoardColumn.of(a.status) != column;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final wide = draggable;

    Widget card(Appointment a) {
      final step = stepOf(a);
      final body = _BoardCard(
        appointment: a,
        showDoctor: showDoctor,
        step: step,
        onOpen: () => onOpen(a),
        onAdvance: () => onAdvance(a),
      );
      // Only a card whose next step leaves this column can be dragged.
      if (!draggable || step == null || BoardColumn.of(step.to) == column) {
        return body;
      }
      return LayoutBuilder(
        builder: (context, box) => LongPressDraggable<Appointment>(
          data: a,
          delay: const Duration(milliseconds: 150),
          feedback: SizedBox(
            width: box.maxWidth,
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(16),
              child: _BoardCard(
                appointment: a,
                showDoctor: showDoctor,
                step: null,
                onOpen: () {},
                onAdvance: () {},
              ),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.35, child: body),
          child: body,
        ),
      );
    }

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (wide)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: [
                Icon(column.icon, size: 18, color: column.color.readableIn(context)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    column.label,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                _Count(appointments.length, color: column.color.readableIn(context)),
              ],
            ),
          ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(wide ? 8 : 0, 0, wide ? 8 : 0, 8),
            children: [
              if (appointments.isEmpty && closed.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'Nothing here',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                ),
              for (final a in appointments)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: card(a),
                ),
              if (closed.isNotEmpty)
                Theme(
                  data: Theme.of(context)
                      .copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(horizontal: 8),
                    childrenPadding: EdgeInsets.zero,
                    title: Text(
                      'Cancelled and no-shows (${closed.length})',
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    children: [
                      for (final a in closed)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Opacity(opacity: 0.7, child: card(a)),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );

    if (!wide) return content;

    return DragTarget<Appointment>(
      onWillAcceptWithDetails: (d) => _lands(d.data),
      onAcceptWithDetails: (d) => onAdvance(d.data),
      builder: (context, candidates, _) {
        final hovering = candidates.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: hovering
                ? column.color.readableIn(context).withAlpha(28)
                : cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: hovering ? column.color.readableIn(context) : cs.outlineVariant,
              width: hovering ? 2 : 1,
            ),
          ),
          child: content,
        );
      },
    );
  }
}

class _Count extends StatelessWidget {
  const _Count(this.value, {required this.color});

  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$value',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}

class _BoardCard extends StatelessWidget {
  const _BoardCard({
    required this.appointment,
    required this.showDoctor,
    required this.step,
    required this.onOpen,
    required this.onAdvance,
  });

  final Appointment appointment;
  final bool showDoctor;
  final BoardStep? step;
  final VoidCallback onOpen;
  final VoidCallback onAdvance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final a = appointment;
    final since = switch (a.status) {
      AppointmentStatus.arrived when a.arrivedAt != null =>
        'Since ${DateFormat.jm().format(a.arrivedAt!)}',
      AppointmentStatus.inConsultation when a.startedAt != null =>
        'Since ${DateFormat.jm().format(a.startedAt!)}',
      _ => null,
    };
    // Within a column the status is mostly the column itself; the badge is
    // for where it is not — waiting vs. with the doctor, or cancelled.
    final showBadge = a.status != AppointmentStatus.pending &&
        a.status != AppointmentStatus.confirmed &&
        a.status != AppointmentStatus.completed;

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.access_time, size: 14, color: cs.primary),
                  const SizedBox(width: 4),
                  Text(
                    DateFormat('h:mm a').format(a.dateTime),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: cs.primary,
                    ),
                  ),
                  const Spacer(),
                  if (showBadge) StatusBadge(status: a.status, small: true),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                a.patient.name,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                a.service,
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (showDoctor)
                Text(
                  'Dr. ${a.doctor.name}',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              if (since != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    since,
                    style: TextStyle(fontSize: 12, color: a.status.color.readableIn(context)),
                  ),
                ),
              if (step case final step?) ...[
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: onAdvance,
                  icon: Icon(step.icon, size: 16),
                  label: Text(step.label),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    textStyle: const TextStyle(fontSize: 13),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
