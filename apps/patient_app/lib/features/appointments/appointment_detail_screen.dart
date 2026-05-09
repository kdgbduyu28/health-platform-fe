import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:api_sdk/api_sdk.dart';

class AppointmentDetailScreen extends ConsumerWidget {
  const AppointmentDetailScreen({super.key, required this.appointmentId});

  final String appointmentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appointments = ref.watch(appointmentsProvider);
    final appointment = appointments.cast<Appointment?>().firstWhere(
          (a) => a?.id == appointmentId,
          orElse: () => null,
        );

    if (appointment == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Appointment')),
        body: const Center(child: Text('Appointment not found.')),
      );
    }

    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final canCancel = appointment.status == AppointmentStatus.pending ||
        appointment.status == AppointmentStatus.confirmed;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Appointment Details'),
        leading: BackButton(onPressed: () => context.pop()),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Hero card
          Container(
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
                StatusBadge(status: appointment.status),
                const SizedBox(height: 12),
                Text(
                  appointment.service,
                  style: theme.textTheme.headlineSmall?.copyWith(
                      color: cs.onPrimary, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  appointment.clinicType.clinicName,
                  style: TextStyle(
                      color: cs.onPrimary.withAlpha(200), fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Date & Time
          _InfoCard(
            children: [
              _InfoTile(
                icon: Icons.calendar_today_outlined,
                label: 'Date',
                value: DateFormat('EEEE, MMMM d, y')
                    .format(appointment.dateTime),
              ),
              _InfoTile(
                icon: Icons.access_time_outlined,
                label: 'Time',
                value: DateFormat('h:mm a').format(appointment.dateTime),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Doctor
          _InfoCard(
            children: [
              Row(
                children: [
                  DoctorAvatar(doctor: appointment.doctor, radius: 28),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Dr. ${appointment.doctor.name}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 16)),
                      Text(appointment.doctor.specialty,
                          style: TextStyle(color: cs.onSurfaceVariant)),
                    ],
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Notes
          if (appointment.notes != null) ...[
            _InfoCard(
              children: [
                Text('Notes',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant)),
                const SizedBox(height: 6),
                Text(appointment.notes!),
              ],
            ),
            const SizedBox(height: 12),
          ],

          // Cancel button
          if (canCancel) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _showCancelDialog(context, ref, appointment),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
              ),
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('Cancel Appointment'),
            ),
          ],
        ],
      ),
    );
  }

  void _showCancelDialog(
      BuildContext context, WidgetRef ref, Appointment appointment) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Appointment'),
        content:
            const Text('Are you sure you want to cancel this appointment?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Keep'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              ref
                  .read(appointmentsProvider.notifier)
                  .updateStatus(appointment.id, AppointmentStatus.cancelled);
              Navigator.pop(ctx);
              context.pop();
            },
            child: const Text('Cancel Appointment'),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile(
      {required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: cs.primary),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style:
                      TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
              Text(value,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }
}
