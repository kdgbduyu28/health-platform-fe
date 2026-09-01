import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:api_sdk/api_sdk.dart';

class BookAppointmentScreen extends ConsumerStatefulWidget {
  const BookAppointmentScreen({super.key});

  @override
  ConsumerState<BookAppointmentScreen> createState() =>
      _BookAppointmentScreenState();
}

class _BookAppointmentScreenState
    extends ConsumerState<BookAppointmentScreen> {
  int _step = 0;
  Service? _service;
  Doctor? _doctor;
  DateTime? _date;
  String? _timeSlot;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final servicesAsync = ref.watch(servicesProvider);
    final doctorsAsync = ref.watch(doctorsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Book Appointment'),
        leading: _step == 0
            ? BackButton(onPressed: () => context.pop())
            : BackButton(onPressed: () => setState(() => _step--)),
      ),
      body: Column(
        children: [
          _StepIndicator(step: _step),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: switch (_step) {
                0 => AsyncView(
                    value: servicesAsync,
                    onRetry: () => ref.invalidate(servicesProvider),
                    builder: (services) => _ServiceStep(
                      services: services,
                      selected: _service,
                      onSelect: (s) => setState(() {
                        _service = s;
                        _step = 1;
                      }),
                    ),
                  ),
                1 => AsyncView(
                    value: doctorsAsync,
                    onRetry: () => ref.invalidate(doctorsProvider),
                    builder: (doctors) => _DoctorStep(
                      doctors: doctors,
                      selected: _doctor,
                      onSelect: (d) => setState(() {
                        _doctor = d;
                        _step = 2;
                      }),
                    ),
                  ),
                2 => _DateTimeStep(
                    doctor: _doctor,
                    selectedDate: _date,
                    selectedSlot: _timeSlot,
                    onDateSelected: (d) => setState(() {
                      _date = d;
                      _timeSlot = null;
                    }),
                    onSlotSelected: (s) => setState(() {
                      _timeSlot = s;
                      _step = 3;
                    }),
                  ),
                _ => _ConfirmStep(
                    service: _service?.name,
                    doctor: _doctor,
                    date: _date,
                    timeSlot: _timeSlot,
                    busy: _busy,
                    onConfirm: _confirm,
                  ),
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirm() async {
    final service = _service;
    final doctor = _doctor;
    final date = _date;
    final slot = _timeSlot;
    if (service == null || doctor == null || date == null || slot == null) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final clinicId = ref.read(currentClinicIdProvider);
    final patient = ref.read(myPatientProvider).value;

    if (clinicId == null) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Still loading the clinic. Try again in a moment.'),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    // A signup creates an account and a profile, but not a patient chart —
    // that link is made by the clinic. Without it there is no patient_id to
    // book against, and RLS would reject the insert anyway.
    if (patient == null) {
      messenger.showSnackBar(const SnackBar(
        content: Text(
          'Your account is not linked to a patient record yet. '
          'Please contact the clinic.',
        ),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    final parts = slot.split(':');
    final scheduledAt = DateTime(
      date.year,
      date.month,
      date.day,
      int.parse(parts[0]),
      int.parse(parts[1]),
    );

    setState(() => _busy = true);
    try {
      await ref.read(appointmentsProvider.notifier).book(
            clinicId: clinicId,
            patientId: patient.id,
            doctorId: doctor.id,
            serviceId: service.id,
            serviceName: service.name,
            scheduledAt: scheduledAt,
          );
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(
        content: Text('Appointment requested. The clinic will confirm it.'),
        behavior: SnackBarBehavior.floating,
      ));
      context.go('/appointments');
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(describeError(e)),
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.step});
  final int step;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final labels = ['Service', 'Doctor', 'Schedule', 'Confirm'];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        children: List.generate(labels.length, (i) {
          final active = i == step;
          final done = i < step;
          return Expanded(
            child: Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: done || active ? cs.primary : cs.surfaceContainerHighest,
                  child: done
                      ? Icon(Icons.check, size: 14, color: cs.onPrimary)
                      : Text(
                          '${i + 1}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: active ? cs.onPrimary : cs.outline,
                          ),
                        ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    labels[i],
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: active ? FontWeight.bold : FontWeight.normal,
                      color: active ? cs.primary : cs.outline,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (i < labels.length - 1)
                  Expanded(
                    child: Divider(color: cs.outlineVariant, thickness: 1),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

class _ServiceStep extends StatelessWidget {
  const _ServiceStep({
    required this.services,
    required this.selected,
    required this.onSelect,
  });

  final List<Service> services;
  final Service? selected;
  final ValueChanged<Service> onSelect;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (services.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: Text('This clinic has no bookable services.')),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Select a service',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: services.map((s) {
            final isSelected = s.id == selected?.id;
            return FilterChip(
              label: Text('${s.name} · ${s.durationMinutes}m'),
              selected: isSelected,
              onSelected: (_) => onSelect(s),
              selectedColor: cs.primaryContainer,
              checkmarkColor: cs.onPrimaryContainer,
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _DoctorStep extends StatelessWidget {
  const _DoctorStep({
    required this.doctors,
    required this.selected,
    required this.onSelect,
  });

  final List<Doctor> doctors;
  final Doctor? selected;
  final ValueChanged<Doctor> onSelect;

  @override
  Widget build(BuildContext context) {
    if (doctors.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: Text('No doctors are available right now.')),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Choose a doctor',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        ...doctors.map((d) {
          final isSelected = d.id == selected?.id;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _DoctorTile(
              doctor: d,
              isSelected: isSelected,
              onTap: () => onSelect(d),
            ),
          );
        }),
      ],
    );
  }
}

class _DoctorTile extends StatelessWidget {
  const _DoctorTile(
      {required this.doctor,
      required this.isSelected,
      required this.onTap});

  final Doctor doctor;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isSelected ? cs.primary : cs.outlineVariant,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: ListTile(
        onTap: onTap,
        leading: DoctorAvatar(doctor: doctor),
        title: Text('Dr. ${doctor.name}',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(doctor.specialty),
        trailing: isSelected
            ? Icon(Icons.check_circle, color: cs.primary)
            : null,
      ),
    );
  }
}

class _DateTimeStep extends StatelessWidget {
  const _DateTimeStep({
    required this.doctor,
    required this.selectedDate,
    required this.selectedSlot,
    required this.onDateSelected,
    required this.onSlotSelected,
  });

  final Doctor? doctor;
  final DateTime? selectedDate;
  final String? selectedSlot;
  final ValueChanged<DateTime> onDateSelected;
  final ValueChanged<String> onSlotSelected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final slots = doctor?.availableTimeSlots ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Pick a date & time',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: DateTime.now().add(const Duration(days: 1)),
              firstDate: DateTime.now(),
              lastDate: DateTime.now().add(const Duration(days: 60)),
              selectableDayPredicate: (day) =>
                  doctor?.availableWeekdays.contains(day.weekday) ?? true,
            );
            if (picked != null) onDateSelected(picked);
          },
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
          icon: const Icon(Icons.calendar_today),
          label: Text(
            selectedDate == null
                ? 'Select date'
                : DateFormat('EEEE, MMMM d, y').format(selectedDate!),
          ),
        ),
        if (selectedDate != null) ...[
          const SizedBox(height: 20),
          Text('Available time slots',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: slots.map((s) {
              final isSelected = s == selectedSlot;
              return ChoiceChip(
                label: Text(s),
                selected: isSelected,
                onSelected: (_) => onSlotSelected(s),
                selectedColor: cs.primaryContainer,
              );
            }).toList(),
          ),
        ],
      ],
    );
  }
}

class _ConfirmStep extends StatelessWidget {
  const _ConfirmStep({
    required this.service,
    required this.doctor,
    required this.date,
    required this.timeSlot,
    required this.busy,
    required this.onConfirm,
  });

  final String? service;
  final Doctor? doctor;
  final DateTime? date;
  final String? timeSlot;
  final bool busy;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Confirm appointment',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 20),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              _SummaryRow(label: 'Service', value: service ?? ''),
              const Divider(height: 24),
              _SummaryRow(
                  label: 'Doctor', value: 'Dr. ${doctor?.name ?? ''}'),
              const Divider(height: 24),
              _SummaryRow(
                  label: 'Specialty', value: doctor?.specialty ?? ''),
              const Divider(height: 24),
              _SummaryRow(
                label: 'Date',
                value: date != null
                    ? DateFormat('EEEE, MMMM d, y').format(date!)
                    : '',
              ),
              const Divider(height: 24),
              _SummaryRow(label: 'Time', value: timeSlot ?? ''),
            ],
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: busy ? null : onConfirm,
          child: busy
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Confirm Booking'),
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }
}
