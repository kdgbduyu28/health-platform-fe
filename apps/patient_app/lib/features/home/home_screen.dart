import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:api_sdk/api_sdk.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clinicType = ref.watch(clinicTypeProvider);
    final upcoming = ref.watch(myUpcomingAppointmentsProvider);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Good day, Juan',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
                Text(
                  clinicType.clinicName,
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
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
                      clinicType.displayName,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: cs.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            sliver: SliverList.list(
              children: [
                if (upcoming.isNotEmpty) ...[
                  _NextAppointmentCard(
                    appointment: upcoming.first,
                    onTap: () =>
                        context.push('/appointments/${upcoming.first.id}'),
                  ),
                ] else
                  _EmptyCard(clinicType: clinicType),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => context.push('/appointments/book'),
                  icon: const Icon(Icons.add),
                  label: const Text('Book Appointment'),
                ),
                if (upcoming.length > 1) ...[
                  const SizedBox(height: 24),
                  Text(
                    'Upcoming',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  ...upcoming.skip(1).take(3).map(
                        (a) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: AppointmentCard(
                            appointment: a,
                            onTap: () =>
                                context.push('/appointments/${a.id}'),
                          ),
                        ),
                      ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NextAppointmentCard extends StatelessWidget {
  const _NextAppointmentCard(
      {required this.appointment, required this.onTap});

  final Appointment appointment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [cs.primary, cs.secondary],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Next Appointment',
                  style: TextStyle(
                      color: cs.onPrimary.withAlpha(200), fontSize: 12),
                ),
                const Spacer(),
                StatusBadge(status: appointment.status),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              appointment.service,
              style: theme.textTheme.titleLarge?.copyWith(
                  color: cs.onPrimary, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Dr. ${appointment.doctor.name}',
              style: TextStyle(
                  color: cs.onPrimary.withAlpha(220), fontSize: 14),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _Chip(
                  icon: Icons.calendar_today,
                  text: DateFormat('EEE, MMM d').format(appointment.dateTime),
                  color: cs.onPrimary,
                ),
                const SizedBox(width: 8),
                _Chip(
                  icon: Icons.access_time,
                  text: DateFormat('h:mm a').format(appointment.dateTime),
                  color: cs.onPrimary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(
      {required this.icon, required this.text, required this.color});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withAlpha(50),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(color: color, fontSize: 12)),
        ],
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.clinicType});
  final ClinicType clinicType;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Icon(clinicType.icon, size: 48, color: cs.outline),
          const SizedBox(height: 12),
          Text('No upcoming appointments',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('Book your first appointment below',
              style: TextStyle(color: cs.outline)),
        ],
      ),
    );
  }
}
