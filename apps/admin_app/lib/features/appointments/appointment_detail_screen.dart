import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:api_sdk/api_sdk.dart';

class AdminAppointmentDetailScreen extends ConsumerWidget {
  const AdminAppointmentDetailScreen({super.key, required this.appointmentId});
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
    void openHistory() =>
        context.openInClinic('/patients/${appointment.patient.id}');

    final header = Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: VisitHeader(
        appointment: appointment,
        who: '${appointment.patient.name} · Dr. ${appointment.doctor.name}',
      ),
    );
    final patient = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Patient info
        _Section(
          title: 'Patient',
          action: TextButton.icon(
            onPressed: openHistory,
            icon: const Icon(Icons.history, size: 16),
            label: const Text('History'),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Row2(
                icon: Icons.person_outline,
                label: 'Name',
                value: appointment.patient.name,
              ),
              _Row2(
                icon: Icons.phone_outlined,
                label: 'Phone',
                value: appointment.patient.phone,
              ),
              _Row2(
                icon: Icons.email_outlined,
                label: 'Email',
                value: appointment.patient.email,
              ),
              if (appointment.patient.age != null)
                _Row2(
                  icon: Icons.cake_outlined,
                  label: 'Age',
                  value: '${appointment.patient.age} years old',
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
    final doctor = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
                  Text(
                    'Dr. ${appointment.doctor.name}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    appointment.doctor.specialty,
                    style: TextStyle(color: cs.onSurfaceVariant),
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
    final chart = DentalChartSection(
      patient: appointment.patient,
      appointment: appointment,
    );
    final clinical = <Widget>[
      // Clinical notes and history — admins are clinicians for this
      // purpose (the clinic owner is often a doctor).
      ChartNoteSection(patient: appointment.patient),
      PreviousVisitsSection(
        appointment: appointment,
        onOpenHistory: openHistory,
        onOpenAppointment: (a) => context.openInClinic('/appointments/${a.id}'),
      ),
      VisitNoteSection(appointment: appointment),
      PatientNoteSection(appointment: appointment),
    ];
    final bill = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        VisitBillSection(
          appointment: appointment,
          onOpenInvoice: (id) => context.pushInClinic('/billing/$id'),
        ),
        const SizedBox(height: 12),
      ],
    );
    // The visit's next steps. An admin may take any of them.
    final actions = _actions(context, ref, appointment);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Appointment Details'),
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
              // On a phone, the page reads top to bottom as before; on a wide
              // screen the visit and its next steps sit on the left, the
              // clinical record beside them.
              narrow: [
                header,
                patient,
                doctor,
                ...clinical.take(2),
                chart,
                ...clinical.skip(2),
                bill,
                ...actions,
              ],
              // The next step right under the header, above the fold on a
              // tablet held sideways.
              start: [
                header,
                if (actions.isNotEmpty) ...[
                  ...actions,
                  const SizedBox(height: 8),
                ],
                patient,
                doctor,
                bill,
              ],
              end: clinical,
              below: [chart],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _actions(
    BuildContext context,
    WidgetRef ref,
    Appointment appointment,
  ) {
    final a = appointment;
    Widget step(
      AppointmentStatus to,
      IconData icon,
      String label,
      String done,
    ) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: FilledButton.icon(
        onPressed: () => changeAppointmentStatus(context, ref, a, to, done: done),
        icon: Icon(icon),
        label: Text(label),
      ),
    );

    return [
      if (a.status == AppointmentStatus.pending)
        step(
          AppointmentStatus.confirmed,
          Icons.check_circle_outline,
          'Confirm appointment',
          'Appointment confirmed',
        ),
      if (a.status == AppointmentStatus.confirmed)
        step(
          AppointmentStatus.arrived,
          Icons.how_to_reg,
          'Check in',
          'Checked in',
        ),
      if (a.status == AppointmentStatus.confirmed ||
          a.status == AppointmentStatus.arrived)
        step(
          AppointmentStatus.inConsultation,
          Icons.play_arrow,
          'Start consultation',
          'Consultation started',
        ),
      // Marking done bills the services performed; the bill opens next.
      if (a.status == AppointmentStatus.arrived ||
          a.status == AppointmentStatus.inConsultation ||
          a.status == AppointmentStatus.completed)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: a.status == AppointmentStatus.completed
              ? OutlinedButton.icon(
                  onPressed: () => showCompleteVisitSheet(context, ref, a),
                  icon: const Icon(Icons.checklist),
                  label: const Text('Services done'),
                )
              : FilledButton.icon(
                  onPressed: () async {
                    final id = await showCompleteVisitSheet(context, ref, a);
                    if (id != null && id.isNotEmpty && context.mounted) {
                      context.pushInClinic('/billing/$id');
                    }
                  },
                  icon: const Icon(Icons.task_alt),
                  label: const Text('Mark done'),
                ),
        ),
      if (a.status == AppointmentStatus.confirmed &&
          !a.dateTime.isAfter(DateTime.now()))
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: OutlinedButton.icon(
            onPressed: () => changeAppointmentStatus(
              context,
              ref,
              a,
              AppointmentStatus.noShow,
              done: 'Marked as a no-show',
            ),
            icon: const Icon(Icons.person_off_outlined),
            label: const Text('Mark as no-show'),
          ),
        ),
      if (a.canReschedule)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: OutlinedButton.icon(
            onPressed: () => showRescheduleSheet(context, a, staff: true),
            icon: const Icon(Icons.edit_calendar_outlined),
            label: const Text('Reschedule'),
          ),
        ),
      if (a.status.staffCanCancel)
        OutlinedButton.icon(
          onPressed: () async {
            final cancelled = await confirmAndCancelAppointment(
              context,
              ref,
              a,
              who: a.patient.name,
            );
            if (cancelled && context.mounted) context.pop();
          },
          style: OutlinedButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
            side: BorderSide(color: Theme.of(context).colorScheme.error),
          ),
          icon: const Icon(Icons.cancel_outlined),
          label: const Text('Cancel appointment'),
        ),
    ];
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
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
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
          Text(
            '$label: ',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
          ),
          Expanded(
            child: value.trim().isEmpty
                ? Text(
                    'Not on file',
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                      fontSize: 13,
                    ),
                  )
                : SelectableText(
                    value,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
          ),
        ],
      ),
    );
  }
}
