import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:api_sdk/api_sdk.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clinicType = ref.watch(clinicTypeProvider);
    final todayAppts = ref.watch(todayAppointmentsProvider);
    final allClinic = ref.watch(clinicAppointmentsProvider);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final pending =
        todayAppts.where((a) => a.status == AppointmentStatus.pending).length;
    final confirmed =
        todayAppts.where((a) => a.status == AppointmentStatus.confirmed).length;
    final completed =
        todayAppts.where((a) => a.status == AppointmentStatus.completed).length;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Admin Dashboard',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: cs.onSurfaceVariant)),
                Text(clinicType.clinicName,
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    DateFormat('MMM d, y').format(DateTime.now()),
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: cs.onPrimaryContainer),
                  ),
                ),
              ),
            ],
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            sliver: SliverList.list(
              children: [
                // Stats row
                Text("Today's Overview",
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _StatCard(
                        label: 'Total',
                        value: todayAppts.length,
                        icon: Icons.event,
                        color: cs.primary),
                    const SizedBox(width: 8),
                    _StatCard(
                        label: 'Pending',
                        value: pending,
                        icon: Icons.schedule,
                        color: AppointmentStatus.pending.color),
                    const SizedBox(width: 8),
                    _StatCard(
                        label: 'Confirmed',
                        value: confirmed,
                        icon: Icons.check_circle_outline,
                        color: AppointmentStatus.confirmed.color),
                    const SizedBox(width: 8),
                    _StatCard(
                        label: 'Done',
                        value: completed,
                        icon: Icons.task_alt,
                        color: AppointmentStatus.completed.color),
                  ],
                ),
                const SizedBox(height: 24),

                // Quick stats – all time
                Row(
                  children: [
                    Expanded(
                      child: _BigStatCard(
                        label: 'Total Patients',
                        value: MockData.patients.length,
                        icon: Icons.group_outlined,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _BigStatCard(
                        label: 'All Appointments',
                        value: allClinic.length,
                        icon: Icons.calendar_month_outlined,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Today's timeline
                Row(
                  children: [
                    Text("Today's Schedule",
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    TextButton(
                      onPressed: () => context.go('/schedule'),
                      child: const Text('View All'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (todayAppts.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                        child: Text('No appointments scheduled today.')),
                  )
                else
                  ...todayAppts.map(
                    (a) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: AppointmentCard(
                        appointment: a,
                        onTap: () => context.push('/appointments/${a.id}'),
                        showPatient: true,
                      ),
                    ),
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
  const _StatCard(
      {required this.label,
      required this.value,
      required this.icon,
      required this.color});

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
            Text('$value',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: color)),
            Text(label,
                style: TextStyle(fontSize: 10, color: color),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _BigStatCard extends StatelessWidget {
  const _BigStatCard(
      {required this.label, required this.value, required this.icon});

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
              Text('$value',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 22)),
              Text(label,
                  style: TextStyle(
                      fontSize: 11, color: cs.onSurfaceVariant)),
            ],
          ),
        ],
      ),
    );
  }
}
