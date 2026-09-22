import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:api_sdk/api_sdk.dart';

class DoctorAppointmentDetailScreen extends ConsumerWidget {
  const DoctorAppointmentDetailScreen({super.key, required this.appointmentId});
  final String appointmentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appointmentAsync = ref.watch(appointmentByIdProvider(appointmentId));

    final guard = asyncGuard(
      appointmentAsync,
      appBar: AppBar(title: const Text('Appointment')),
      onRetry: () => ref.invalidate(appointmentsProvider),
    );
    if (guard != null) return guard;

    final appointment = appointmentAsync.requireValue;
    if (appointment == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Appointment')),
        body: const Center(child: Text('Not found.')),
      );
    }

    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final patient = appointment.patient;
    void openHistory() => context.pushInClinic('/patients/${patient.id}');

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
                if (appointment.rescheduledFrom case final from?)
                  Text(
                    'Moved from ${DateFormat('EEE, MMM d · h:mm a').format(from)}',
                    style: TextStyle(
                        color: cs.onPrimary.withAlpha(180), fontSize: 12),
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
                Row(
                  children: [
                    Text('Patient',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: cs.onSurfaceVariant,
                            fontSize: 12)),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: openHistory,
                      icon: const Icon(Icons.history, size: 16),
                      label: const Text('History'),
                    ),
                  ],
                ),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: cs.secondaryContainer,
                      child: Text(
                        patient.initials,
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: cs.onSecondaryContainer),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(patient.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 16)),
                          Text(patient.phone,
                              style: TextStyle(color: cs.onSurfaceVariant)),
                          if (patient.age != null)
                            Text('Age ${patient.age}',
                                style: TextStyle(color: cs.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // What the consult needs, in the order it is needed: what is on
          // file, what happened last time, then today's notes.
          ChartNoteSection(patient: patient),
          PreviousVisitsSection(
            appointment: appointment,
            onOpenHistory: openHistory,
            onOpenAppointment: (a) => context.pushInClinic('/appointments/${a.id}'),
          ),
          VisitNoteSection(appointment: appointment),
          PatientNoteSection(appointment: appointment),
          const SizedBox(height: 12),

          // Actions: the next step of the visit, once it has been saved.
          if (appointment.status == AppointmentStatus.pending)
            FilledButton.icon(
              onPressed: () => changeAppointmentStatus(
                  context, ref, appointment, AppointmentStatus.confirmed,
                  done: 'Appointment confirmed'),
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Confirm appointment'),
            ),
          if (appointment.status == AppointmentStatus.confirmed ||
              appointment.status == AppointmentStatus.arrived)
            FilledButton.icon(
              onPressed: () => changeAppointmentStatus(
                  context, ref, appointment, AppointmentStatus.inConsultation,
                  done: 'Consultation started'),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start consultation'),
            ),
          if (appointment.status == AppointmentStatus.inConsultation)
            FilledButton.icon(
              onPressed: () async {
                final saved = await changeAppointmentStatus(
                    context, ref, appointment, AppointmentStatus.completed,
                    done: 'Visit completed');
                if (saved && context.mounted) context.pop();
              },
              icon: const Icon(Icons.task_alt),
              label: const Text('Complete visit'),
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
