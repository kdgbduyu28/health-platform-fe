import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:api_sdk/api_sdk.dart';

class AdminAppointmentDetailScreen extends ConsumerStatefulWidget {
  const AdminAppointmentDetailScreen({super.key, required this.appointmentId});
  final String appointmentId;

  @override
  ConsumerState<AdminAppointmentDetailScreen> createState() =>
      _AdminAppointmentDetailScreenState();
}

class _AdminAppointmentDetailScreenState
    extends ConsumerState<AdminAppointmentDetailScreen> {
  final _notesCtrl = TextEditingController();
  bool _editingNotes = false;

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appointments = ref.watch(appointmentsProvider);
    final appointment = appointments.cast<Appointment?>().firstWhere(
          (a) => a?.id == widget.appointmentId,
          orElse: () => null,
        );

    if (appointment == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Appointment')),
        body: const Center(child: Text('Not found.')),
      );
    }

    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final notifier = ref.read(appointmentsProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Appointment Details'),
        leading: BackButton(onPressed: () => context.pop()),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header
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
                Text(appointment.service,
                    style: theme.textTheme.headlineSmall?.copyWith(
                        color: cs.onPrimary, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(
                    '${DateFormat('EEE, MMM d').format(appointment.dateTime)}  ·  ${DateFormat('h:mm a').format(appointment.dateTime)}',
                    style: TextStyle(
                        color: cs.onPrimary.withAlpha(210), fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Patient info
          _Section(
            title: 'Patient',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Row2(
                    icon: Icons.person_outline,
                    label: 'Name',
                    value: appointment.patient.name),
                _Row2(
                    icon: Icons.phone_outlined,
                    label: 'Phone',
                    value: appointment.patient.phone),
                _Row2(
                    icon: Icons.email_outlined,
                    label: 'Email',
                    value: appointment.patient.email),
                if (appointment.patient.age != null)
                  _Row2(
                      icon: Icons.cake_outlined,
                      label: 'Age',
                      value: '${appointment.patient.age} years old'),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Doctor info
          _Section(
            title: 'Doctor',
            child: Row(
              children: [
                DoctorAvatar(doctor: appointment.doctor, radius: 28),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Dr. ${appointment.doctor.name}',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(appointment.doctor.specialty,
                        style:
                            TextStyle(color: cs.onSurfaceVariant)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Notes
          _Section(
            title: 'Notes',
            action: TextButton.icon(
              onPressed: () {
                setState(() {
                  _editingNotes = !_editingNotes;
                  if (_editingNotes) {
                    _notesCtrl.text = appointment.notes ?? '';
                  }
                });
              },
              icon: Icon(_editingNotes ? Icons.close : Icons.edit_outlined,
                  size: 16),
              label: Text(_editingNotes ? 'Cancel' : 'Edit'),
            ),
            child: _editingNotes
                ? Column(
                    children: [
                      TextField(
                        controller: _notesCtrl,
                        maxLines: 4,
                        decoration: const InputDecoration(
                            hintText: 'Add consultation notes…'),
                      ),
                      const SizedBox(height: 8),
                      FilledButton(
                        onPressed: () {
                          notifier.updateNotes(
                              appointment.id, _notesCtrl.text.trim());
                          setState(() => _editingNotes = false);
                        },
                        child: const Text('Save Notes'),
                      ),
                    ],
                  )
                : Text(
                    appointment.notes?.isNotEmpty == true
                        ? appointment.notes!
                        : 'No notes yet.',
                    style: TextStyle(
                        color: appointment.notes?.isNotEmpty == true
                            ? cs.onSurface
                            : cs.outline),
                  ),
          ),
          const SizedBox(height: 24),

          // Action buttons
          if (appointment.status == AppointmentStatus.pending) ...[
            FilledButton.icon(
              onPressed: () {
                notifier.updateStatus(
                    appointment.id, AppointmentStatus.confirmed);
                _showSnack(context, 'Appointment confirmed');
              },
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Confirm Appointment'),
            ),
            const SizedBox(height: 8),
          ],
          if (appointment.status == AppointmentStatus.confirmed) ...[
            FilledButton.icon(
              onPressed: () {
                notifier.updateStatus(
                    appointment.id, AppointmentStatus.completed);
                _showSnack(context, 'Marked as completed');
                context.pop();
              },
              icon: const Icon(Icons.task_alt),
              label: const Text('Mark as Completed'),
            ),
            const SizedBox(height: 8),
          ],
          if (appointment.status == AppointmentStatus.pending ||
              appointment.status == AppointmentStatus.confirmed) ...[
            OutlinedButton.icon(
              onPressed: () => _showCancelDialog(context, appointment, notifier),
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

  void _showSnack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
    ));
  }

  void _showCancelDialog(BuildContext context, Appointment appointment,
      AppointmentsNotifier notifier) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Appointment'),
        content: const Text('This will notify the patient. Continue?'),
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
              context.pop();
            },
            child: const Text('Cancel It'),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.action});
  final String title;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(title,
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: cs.onSurfaceVariant,
                      fontSize: 12)),
              const Spacer(),
              if (action != null) action!,
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _Row2 extends StatelessWidget {
  const _Row2({required this.icon, required this.label, required this.value});
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
          Icon(icon, size: 16, color: cs.primary),
          const SizedBox(width: 8),
          Text('$label: ',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
          Expanded(
              child: Text(value,
                  style: const TextStyle(fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }
}
