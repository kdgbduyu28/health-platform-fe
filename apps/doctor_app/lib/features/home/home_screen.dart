import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:api_sdk/api_sdk.dart';

class DoctorHomeScreen extends ConsumerStatefulWidget {
  const DoctorHomeScreen({super.key});

  @override
  ConsumerState<DoctorHomeScreen> createState() => _DoctorHomeScreenState();
}

class _DoctorHomeScreenState extends ConsumerState<DoctorHomeScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final clinic = ref.watch(currentClinicProvider).value;
    final doctorAsync = ref.watch(currentDoctorProvider);
    final todayAsync = ref.watch(myDoctorTodayProvider);
    final allAsync = ref.watch(myDoctorAppointmentsProvider);

    // The app bar shows tab counts, so it needs values before the lists below
    // can render. Empty is the right stand-in while loading; the tab bodies
    // still show a spinner or a real error through AsyncView.
    final doctor = doctorAsync.value;
    final todayAppts = todayAsync.value ?? const <Appointment>[];
    final upcoming = (allAsync.value ?? const <Appointment>[])
        .where((a) =>
            a.dateTime.isAfter(DateTime.now()) &&
            !a.isToday &&
            a.status.holdsTime)
        .toList();
    // Newest first: the visit a doctor looks back at is usually the last one.
    final past = (allAsync.value ?? const <Appointment>[])
        .where((a) => a.dateTime.isBefore(DateTime.now()) && !a.isToday)
        .toList()
        .reversed
        .toList();

    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          SliverAppBar.large(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Doctors may practise at several clinics; the clinic line is
                // also where they switch between them.
                ClinicTitle(
                  markSize: 20,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
                Text(doctor == null ? 'Doctor' : 'Dr. ${doctor.name}',
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            actions: [
              Container(
                margin: const EdgeInsets.only(right: 16),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(clinic?.icon ?? Icons.local_hospital_outlined,
                        size: 16, color: cs.onPrimaryContainer),
                    const SizedBox(width: 4),
                    Text(
                      doctor?.specialty ?? clinic?.typeName ?? '',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: cs.onPrimaryContainer),
                    ),
                  ],
                ),
              ),
              const AccountMenuButton(),
              const SizedBox(width: 8),
            ],
            bottom: TabBar(
              controller: _tabs,
              tabs: [
                Tab(text: "Today (${todayAppts.length})"),
                Tab(text: "Upcoming (${upcoming.length})"),
                const Tab(text: 'Past'),
              ],
            ),
          ),
        ],
        body: Column(
          children: [
            // Today's stats banner
            if (_tabs.index == 0)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                color: cs.surfaceContainerLow,
                child: Row(
                  children: [
                    for (final (i, (label, status)) in const [
                      ('Waiting', AppointmentStatus.arrived),
                      ('With you', AppointmentStatus.inConsultation),
                      ('Expected', AppointmentStatus.confirmed),
                      ('Done', AppointmentStatus.completed),
                    ].indexed) ...[
                      if (i > 0) const SizedBox(width: 12),
                      _MiniStat(
                        label: label,
                        value: todayAppts.where((a) => a.status == status).length,
                        color: status.color,
                      ),
                    ],
                  ],
                ),
              ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  AsyncView(
                    value: todayAsync,
                    onRetry: () => ref.invalidate(appointmentsProvider),
                    builder: (today) => _TodayQueue(appointments: today),
                  ),
                  AsyncView(
                    value: allAsync,
                    onRetry: () => ref.invalidate(appointmentsProvider),
                    builder: (_) => _AppointmentListTab(
                      appointments: upcoming,
                      emptyMessage: 'No upcoming appointments',
                      showTime: false,
                    ),
                  ),
                  AsyncView(
                    value: allAsync,
                    onRetry: () => ref.invalidate(appointmentsProvider),
                    builder: (_) => _AppointmentListTab(
                      appointments: past,
                      emptyMessage: 'No past appointments',
                      showTime: false,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat(
      {required this.label, required this.value, required this.color});
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('$value',
            style: TextStyle(
                fontWeight: FontWeight.bold, fontSize: 20, color: color)),
        Text(label,
            style: TextStyle(fontSize: 11, color: color)),
      ],
    );
  }
}

class _AppointmentListTab extends StatelessWidget {
  const _AppointmentListTab({
    required this.appointments,
    required this.emptyMessage,
    required this.showTime,
  });

  final List<Appointment> appointments;
  final String emptyMessage;
  final bool showTime;

  @override
  Widget build(BuildContext context) {
    if (appointments.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_available,
                size: 56,
                color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(emptyMessage,
                style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: appointments.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final a = appointments[i];
        return _DoctorApptCard(appointment: a, showTime: showTime);
      },
    );
  }
}

class _DoctorApptCard extends StatelessWidget {
  const _DoctorApptCard({
    required this.appointment,
    required this.showTime,
    this.action,
    this.highlight = false,
  });
  final Appointment appointment;
  final bool showTime;

  /// The next step for this visit (Start, Complete), under its details.
  final Widget? action;

  /// The patient to call in next.
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return Card(
      shape: highlight
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: appointment.status.color, width: 2),
            )
          : null,
      child: InkWell(
        onTap: () =>
            context.pushInClinic('/appointments/${appointment.id}'),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Time column
              if (showTime)
                Container(
                  width: 56,
                  margin: const EdgeInsets.only(right: 12),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    children: [
                      Text(
                        DateFormat('h:mm').format(appointment.dateTime),
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: cs.onPrimaryContainer),
                      ),
                      Text(
                        DateFormat('a').format(appointment.dateTime),
                        style: TextStyle(
                            fontSize: 11,
                            color: cs.onPrimaryContainer),
                      ),
                    ],
                  ),
                ),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            appointment.patient.name,
                            style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                        StatusBadge(
                            status: appointment.status, small: true),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(appointment.service,
                        style: TextStyle(color: cs.onSurfaceVariant)),
                    if (!showTime)
                      Text(
                        DateFormat('EEE, MMM d').format(appointment.dateTime),
                        style: TextStyle(
                            fontSize: 12,
                            color: cs.primary),
                      ),
                    if (appointment.status == AppointmentStatus.arrived &&
                        appointment.arrivedAt != null)
                      Text(
                        'Arrived ${DateFormat.jm().format(appointment.arrivedAt!)}',
                        style: TextStyle(
                            fontSize: 12, color: appointment.status.color),
                      ),
                    if (action != null) ...[
                      const SizedBox(height: 8),
                      action!,
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

/// Today, as a doctor works through it: who is in with them, who is in the
/// waiting room (in order of arrival), who is still to come, and who is done.
class _TodayQueue extends ConsumerWidget {
  const _TodayQueue({required this.appointments});

  final List<Appointment> appointments;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    List<Appointment> where(bool Function(AppointmentStatus) test) =>
        [...appointments.where((a) => test(a.status))];

    final withMe = where((s) => s == AppointmentStatus.inConsultation);
    final waiting = where((s) => s == AppointmentStatus.arrived)
      ..sort((a, b) => (a.arrivedAt ?? a.dateTime)
          .compareTo(b.arrivedAt ?? b.dateTime));
    final later = where((s) =>
        s == AppointmentStatus.pending || s == AppointmentStatus.confirmed);
    final done = where((s) => !s.isOpen);

    if (appointments.isEmpty) {
      return const _AppointmentListTab(
        appointments: [],
        emptyMessage: 'No appointments today',
        showTime: true,
      );
    }

    Widget start(Appointment a) => FilledButton.tonalIcon(
          onPressed: () => changeAppointmentStatus(
              context, ref, a, AppointmentStatus.inConsultation,
              done: 'Consultation with ${a.patient.name} started'),
          icon: const Icon(Icons.play_arrow, size: 18),
          label: const Text('Start consultation'),
        );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (withMe.isNotEmpty) ...[
          const _QueueHeader('With you now'),
          for (final a in withMe)
            _DoctorApptCard(
              appointment: a,
              showTime: true,
              highlight: true,
              action: FilledButton.icon(
                onPressed: () => changeAppointmentStatus(
                    context, ref, a, AppointmentStatus.completed,
                    done: 'Visit completed'),
                icon: const Icon(Icons.task_alt, size: 18),
                label: const Text('Complete visit'),
              ),
            ),
        ],
        if (waiting.isNotEmpty) ...[
          _QueueHeader('Waiting room (${waiting.length})'),
          for (final (i, a) in waiting.indexed)
            _DoctorApptCard(
              appointment: a,
              showTime: true,
              highlight: i == 0 && withMe.isEmpty,
              action: start(a),
            ),
        ],
        if (later.isNotEmpty) ...[
          const _QueueHeader('Later today'),
          for (final a in later)
            _DoctorApptCard(
              appointment: a,
              showTime: true,
              // Clinics with nobody at the desk start straight from here.
              action: a.status == AppointmentStatus.confirmed ? start(a) : null,
            ),
        ],
        if (done.isNotEmpty) ...[
          const _QueueHeader('Done today'),
          for (final a in done) _DoctorApptCard(appointment: a, showTime: true),
        ],
      ],
    );
  }
}

class _QueueHeader extends StatelessWidget {
  const _QueueHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .titleSmall
            ?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }
}
