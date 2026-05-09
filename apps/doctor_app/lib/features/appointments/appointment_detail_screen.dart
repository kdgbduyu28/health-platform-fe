import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:api_sdk/api_sdk.dart';

class DoctorAppointmentDetailScreen extends ConsumerStatefulWidget {
  const DoctorAppointmentDetailScreen(
      {super.key, required this.appointmentId});
  final String appointmentId;

  @override
  ConsumerState<DoctorAppointmentDetailScreen> createState() =>
      _DoctorAppointmentDetailScreenState();
}

class _DoctorAppointmentDetailScreenState
    extends ConsumerState<DoctorAppointmentDetailScreen> {
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
        title: const Text('Patient Appointment'),
        leading: BackButton(onPressed: () => context.pop()),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header card
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
                  DateFormat('EEEE, MMMM d · h:mm a')
                      .format(appointment.dateTime),
                  style: TextStyle(
                      color: cs.onPrimary.withAlpha(210), fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Patient card
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Patient',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant,
                        fontSize: 12)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: cs.secondaryContainer,
                      child: Text(
                        appointment.patient.initials,
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: cs.onSecondaryContainer),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(appointment.patient.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 16)),
                        Text(appointment.patient.phone,
                            style:
                                TextStyle(color: cs.onSurfaceVariant)),
                        if (appointment.patient.age != null)
                          Text('Age ${appointment.patient.age}',
                              style: TextStyle(color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ],
                ),
                if (appointment.patient.medicalNotes != null) ...[
                  const Divider(height: 20),
                  Text('Medical Notes',
                      style: TextStyle(
                          fontSize: 12, color: cs.onSurfaceVariant)),
                  const SizedBox(height: 4),
                  Text(appointment.patient.medicalNotes!),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Consultation notes
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Consultation Notes',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: cs.onSurfaceVariant,
                            fontSize: 12)),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () => setState(() {
                        _editingNotes = !_editingNotes;
                        if (_editingNotes) {
                          _notesCtrl.text = appointment.notes ?? '';
                        }
                      }),
                      icon: Icon(
                          _editingNotes ? Icons.close : Icons.edit_outlined,
                          size: 16),
                      label: Text(_editingNotes ? 'Cancel' : 'Edit'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_editingNotes) ...[
                  TextField(
                    controller: _notesCtrl,
                    maxLines: 5,
                    decoration: const InputDecoration(
                        hintText: 'Write your consultation notes…'),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: () {
                      notifier.updateNotes(
                          appointment.id, _notesCtrl.text.trim());
                      setState(() => _editingNotes = false);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Notes saved'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    child: const Text('Save Notes'),
                  ),
                ] else
                  Text(
                    appointment.notes?.isNotEmpty == true
                        ? appointment.notes!
                        : 'No notes yet. Tap Edit to add.',
                    style: TextStyle(
                        color: appointment.notes?.isNotEmpty == true
                            ? cs.onSurface
                            : cs.outline),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Actions
          if (appointment.status == AppointmentStatus.confirmed)
            FilledButton.icon(
              onPressed: () {
                notifier.updateStatus(
                    appointment.id, AppointmentStatus.completed);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Appointment marked as completed'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                context.pop();
              },
              icon: const Icon(Icons.task_alt),
              label: const Text('Mark as Completed'),
            ),
          if (appointment.status == AppointmentStatus.pending)
            FilledButton.icon(
              onPressed: () {
                notifier.updateStatus(
                    appointment.id, AppointmentStatus.confirmed);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Appointment confirmed'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Confirm Appointment'),
            ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

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
      child: child,
    );
  }
}
