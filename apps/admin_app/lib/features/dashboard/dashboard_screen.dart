import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:api_sdk/api_sdk.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todayAsync = ref.watch(todayAppointmentsProvider);
    final upcomingAsync = ref.watch(upcomingAppointmentsProvider);
    final patientCount = ref.watch(patientCountProvider).value;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final todayAppts = todayAsync.value ?? const <Appointment>[];
    final upcoming = upcomingAsync.value ?? const <Appointment>[];

    final pending = todayAppts
        .where((a) => a.status == AppointmentStatus.pending)
        .length;
    // Checked in and waiting, or with a doctor.
    final inClinic = todayAppts.where((a) => a.status.isOnSite).length;
    final completed = todayAppts
        .where((a) => a.status == AppointmentStatus.completed)
        .length;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The date on the line above, so it is not in a chip too.
                Text(
                  DateFormat('EEEE, MMMM d').format(DateTime.now()),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                ClinicTitle(
                  page: 'Dashboard',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            actions: [
              const NotificationsButton(),
              const AccountMenuButton(),
              const SizedBox(width: 8),
            ],
          ),
          SliverCentered(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            sliver: SliverList.list(
              children: [
                // Stats row
                Text(
                  "Today's Overview",
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, box) {
                    final today = Row(
                      children: [
                        _StatCard(
                          label: 'Total',
                          value: todayAppts.length,
                          icon: Icons.event,
                          color: cs.primary,
                        ),
                        const SizedBox(width: 8),
                        _StatCard(
                          label: 'Pending',
                          value: pending,
                          icon: Icons.schedule,
                          color: AppointmentStatus.pending.color.readableIn(context),
                        ),
                        const SizedBox(width: 8),
                        _StatCard(
                          label: 'In clinic',
                          value: inClinic,
                          icon: Icons.chair_outlined,
                          color: AppointmentStatus.arrived.color.readableIn(context),
                        ),
                        const SizedBox(width: 8),
                        _StatCard(
                          label: 'Done',
                          value: completed,
                          icon: Icons.task_alt,
                          color: AppointmentStatus.completed.color.readableIn(context),
                        ),
                      ],
                    );
                    // The clinic at large
                    final overall = Row(
                      children: [
                        Expanded(
                          child: _BigStatCard(
                            label: 'Total Patients',
                            value: patientCount ?? 0,
                            icon: Icons.group_outlined,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _BigStatCard(
                            label: 'Upcoming',
                            value: upcoming.length,
                            icon: Icons.calendar_month_outlined,
                          ),
                        ),
                      ],
                    );
                    // Room for both on one line: today on the left, the
                    // clinic at large on the right.
                    if (box.maxWidth >= Breakpoints.twoPane) {
                      return IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(flex: 3, child: today),
                            const SizedBox(width: 12),
                            Expanded(flex: 2, child: overall),
                          ],
                        ),
                      );
                    }
                    return Column(
                      children: [today, const SizedBox(height: 24), overall],
                    );
                  },
                ),
                const SizedBox(height: 24),

                // Today's timeline
                Row(
                  children: [
                    Text(
                      "Today's Schedule",
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => context.goInClinic('/schedule'),
                      child: const Text('View All'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (!todayAsync.hasValue)
                  AsyncView(
                    value: todayAsync,
                    onRetry: () => ref.invalidate(appointmentsProvider),
                    builder: (_) => const SizedBox.shrink(),
                  )
                else if (todayAppts.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text('No appointments scheduled today.'),
                    ),
                  )
                else
                  CardColumns(
                    children: [
                      for (final a in todayAppts)
                        AppointmentCard(
                          appointment: a,
                          onTap: () =>
                              context.pushInClinic('/appointments/${a.id}'),
                          showPatient: true,
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final int value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withAlpha(25),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withAlpha(60)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text(
              '$value',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(fontSize: 10, color: color),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _BigStatCard extends StatelessWidget {
  const _BigStatCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final int value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: cs.onPrimaryContainer),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$value',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                ),
              ),
              Text(
                label,
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
