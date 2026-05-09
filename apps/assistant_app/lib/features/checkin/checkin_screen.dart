import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:api_sdk/api_sdk.dart';

class CheckInScreen extends ConsumerStatefulWidget {
  const CheckInScreen({super.key});

  @override
  ConsumerState<CheckInScreen> createState() => _CheckInScreenState();
}

class _CheckInScreenState extends ConsumerState<CheckInScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final clinicType = ref.watch(clinicTypeProvider);
    final todayAppts = ref.watch(todayAppointmentsProvider);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final filtered = todayAppts.where((a) {
      if (_query.isEmpty) return true;
      return a.patient.name.toLowerCase().contains(_query.toLowerCase()) ||
          a.patient.phone.contains(_query);
    }).toList();

    final pending = todayAppts
        .where((a) => a.status == AppointmentStatus.pending)
        .length;
    final confirmed = todayAppts
        .where((a) => a.status == AppointmentStatus.confirmed)
        .length;
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
                Text(DateFormat('EEEE, MMMM d').format(DateTime.now()),
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: cs.onSurfaceVariant)),
                Text(clinicType.clinicName,
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          SliverToBoxAdapter(
            child: Column(
              children: [
                // Stats
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      _StatPill(
                          label: 'Pending',
                          value: pending,
                          color: AppointmentStatus.pending.color),
                      const SizedBox(width: 8),
                      _StatPill(
                          label: 'Confirmed',
                          value: confirmed,
                          color: AppointmentStatus.confirmed.color),
                      const SizedBox(width: 8),
                      _StatPill(
                          label: 'Completed',
                          value: completed,
                          color: AppointmentStatus.completed.color),
                    ],
                  ),
                ),
                // Search
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: TextField(
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(
                      hintText: 'Search patient by name or phone…',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _query.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () =>
                                  setState(() => _query = ''),
                            )
                          : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (filtered.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.event_available,
                        size: 56, color: cs.outline),
                    const SizedBox(height: 12),
                    Text(
                      _query.isNotEmpty
                          ? 'No results for "$_query"'
                          : 'No appointments today',
                      style: theme.textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
            )
          else
            SliverList.separated(
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final a = filtered[i];
                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16),
                  child: _CheckInCard(appointment: a),
                );
              },
            ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 16)),
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill(
      {required this.label, required this.value, required this.color});
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding:
            const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withAlpha(25),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withAlpha(60)),
        ),
        child: Column(
          children: [
            Text('$value',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    color: color)),
            Text(label,
                style: TextStyle(fontSize: 11, color: color),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _CheckInCard extends ConsumerWidget {
  const _CheckInCard({required this.appointment});
  final Appointment appointment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final notifier = ref.read(appointmentsProvider.notifier);
    final timeStr = DateFormat('h:mm a').format(appointment.dateTime);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: cs.primaryContainer,
                  child: Text(appointment.patient.initials,
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: cs.onPrimaryContainer)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(appointment.patient.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 15)),
                      Text(appointment.patient.phone,
                          style:
                              TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                    ],
                  ),
                ),
                StatusBadge(status: appointment.status, small: true),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.access_time_outlined,
                    size: 14, color: cs.primary),
                const SizedBox(width: 4),
                Text(timeStr,
                    style: TextStyle(color: cs.primary, fontSize: 13)),
                const SizedBox(width: 12),
                Icon(Icons.medical_services_outlined,
                    size: 14, color: cs.onSurfaceVariant),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(appointment.service,
                      style: TextStyle(
                          color: cs.onSurfaceVariant, fontSize: 13),
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            if (appointment.status == AppointmentStatus.pending ||
                appointment.status == AppointmentStatus.confirmed) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  if (appointment.status == AppointmentStatus.pending)
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => notifier.updateStatus(
                            appointment.id, AppointmentStatus.confirmed),
                        icon: const Icon(Icons.check, size: 16),
                        label: const Text('Confirm'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 36),
                          textStyle: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
                  if (appointment.status == AppointmentStatus.confirmed)
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => notifier.updateStatus(
                            appointment.id, AppointmentStatus.completed),
                        icon: const Icon(Icons.task_alt, size: 16),
                        label: const Text('Check In'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 36),
                          textStyle: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () => _cancel(context, notifier),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      minimumSize: const Size(0, 36),
                      textStyle: const TextStyle(fontSize: 13),
                    ),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _cancel(BuildContext context, AppointmentsNotifier notifier) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Appointment'),
        content: Text('Cancel ${appointment.patient.name}\'s appointment?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Keep')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              notifier.updateStatus(
                  appointment.id, AppointmentStatus.cancelled);
              Navigator.pop(ctx);
            },
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}
