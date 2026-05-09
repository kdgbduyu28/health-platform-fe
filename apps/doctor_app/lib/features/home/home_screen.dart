import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:api_sdk/api_sdk.dart';

class DoctorHomeScreen extends ConsumerStatefulWidget {
  const DoctorHomeScreen({super.key});

  @override
  ConsumerState<DoctorHomeScreen> createState() => _DoctorHomeScreenState();
}

class _DoctorHomeScreenState extends ConsumerState<DoctorHomeScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final clinicType = ref.watch(clinicTypeProvider);
    final doctor = ref.watch(currentDoctorProvider);
    final todayAppts = ref.watch(myDoctorTodayProvider);
    final allAppts = ref.watch(myDoctorAppointmentsProvider);
    final upcoming = allAppts
        .where((a) =>
            a.dateTime.isAfter(DateTime.now()) &&
            !a.isToday &&
            a.status != AppointmentStatus.cancelled)
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
                Text('Welcome back',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: cs.onSurfaceVariant)),
                Text('Dr. ${doctor.name}',
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
                    Icon(clinicType.icon,
                        size: 16, color: cs.onPrimaryContainer),
                    const SizedBox(width: 4),
                    Text(
                      doctor.specialty,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: cs.onPrimaryContainer),
                    ),
                  ],
                ),
              ),
            ],
            bottom: TabBar(
              controller: _tabs,
              tabs: [
                Tab(text: "Today (${todayAppts.length})"),
                Tab(text: "Upcoming (${upcoming.length})"),
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
                    _MiniStat(
                      label: 'Today',
                      value: todayAppts.length,
                      color: cs.primary,
                    ),
                    const SizedBox(width: 12),
                    _MiniStat(
                      label: 'Pending',
                      value: todayAppts
                          .where((a) =>
                              a.status == AppointmentStatus.pending)
                          .length,
                      color: AppointmentStatus.pending.color,
                    ),
                    const SizedBox(width: 12),
                    _MiniStat(
                      label: 'Confirmed',
                      value: todayAppts
                          .where((a) =>
                              a.status == AppointmentStatus.confirmed)
                          .length,
                      color: AppointmentStatus.confirmed.color,
                    ),
                    const SizedBox(width: 12),
                    _MiniStat(
                      label: 'Done',
                      value: todayAppts
                          .where((a) =>
                              a.status == AppointmentStatus.completed)
                          .length,
                      color: AppointmentStatus.completed.color,
                    ),
                  ],
                ),
              ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _AppointmentListTab(
                    appointments: todayAppts,
                    emptyMessage: 'No appointments today',
                    showTime: true,
                  ),
                  _AppointmentListTab(
                    appointments: upcoming,
                    emptyMessage: 'No upcoming appointments',
                    showTime: false,
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
  const _DoctorApptCard(
      {required this.appointment, required this.showTime});
  final Appointment appointment;
  final bool showTime;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return Card(
      child: InkWell(
        onTap: () =>
            context.push('/appointments/${appointment.id}'),
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
