import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
    final patient = appointment.patient;
    void openHistory() => context.openInClinic('/patients/${patient.id}');

    final header = Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: VisitHeader(appointment: appointment, who: patient.name),
    );
    final patientCard = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Patient card
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Patient',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: cs.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
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
                        color: cs.onSecondaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          patient.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          patient.phone.isNotEmpty
                              ? patient.phone
                              : patient.email.isNotEmpty
                                  ? patient.email
                                  : 'No contact info',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                        if (patient.age != null)
                          Text(
                            'Age ${patient.age}',
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
    // Full width under the two columns on a wide screen, so the teeth are
    // big enough to tap on a tablet.
    final chart =
        DentalChartSection(patient: patient, appointment: appointment);
    final clinical = <Widget>[
      // What the consult needs, in the order it is needed: what is on
      // file, what happened last time, the teeth (at a dental clinic),
      // then today's notes.
      ChartNoteSection(patient: patient),
      PreviousVisitsSection(
        appointment: appointment,
        onOpenHistory: openHistory,
        onOpenAppointment: (a) => context.openInClinic('/appointments/${a.id}'),
      ),
      VisitNoteSection(appointment: appointment),
      PatientNoteSection(appointment: appointment),
    ];
    final actions = <Widget>[
      const SizedBox(height: 12),
      // Actions: the next step of the visit, once it has been saved.
      if (appointment.status == AppointmentStatus.pending)
        FilledButton.icon(
          onPressed: () => changeAppointmentStatus(
            context,
            ref,
            appointment,
            AppointmentStatus.confirmed,
            done: 'Appointment confirmed',
          ),
          icon: const Icon(Icons.check_circle_outline),
          label: const Text('Confirm appointment'),
        ),
      if (appointment.status == AppointmentStatus.confirmed ||
          appointment.status == AppointmentStatus.arrived)
        FilledButton.icon(
          onPressed: () => changeAppointmentStatus(
            context,
            ref,
            appointment,
            AppointmentStatus.inConsultation,
            done: 'Consultation started',
          ),
          icon: const Icon(Icons.play_arrow),
          label: const Text('Start consultation'),
        ),
      if (appointment.status == AppointmentStatus.arrived ||
          appointment.status == AppointmentStatus.inConsultation) ...[
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: () async {
            final saved = await showCompleteVisitSheet(context, ref, appointment);
            if (saved != null && context.mounted) context.pop();
          },
          icon: const Icon(Icons.task_alt),
          label: const Text('Mark done'),
        ),
      ],
      if (appointment.status == AppointmentStatus.completed)
        OutlinedButton.icon(
          onPressed: () => showCompleteVisitSheet(context, ref, appointment),
          icon: const Icon(Icons.checklist),
          label: const Text('Services done'),
        ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Patient Appointment'),
        leading: BackButton(onPressed: () => context.pop()),
      ),
      body: CenteredScroll(
        maxWidth: ContentWidth.detail,
        builder: (padding) => ListView(
          padding: padding,
          children: [
            SplitColumns(
              startFlex: 2,
              endFlex: 3,
              // A phone reads top to bottom; a wide screen keeps the visit
              // and its next step on the left, the record beside them.
              narrow: [
                header,
                patientCard,
                ...clinical.take(2),
                chart,
                ...clinical.skip(2),
                ...actions,
              ],
              // The next step right under the header, above the fold on a
              // tablet held sideways.
              start: [
                header,
                ...actions.skip(1),
                const SizedBox(height: 16),
                patientCard,
              ],
              end: clinical,
              below: [chart],
            ),
          ],
        ),
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
