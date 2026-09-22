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

  /// A start time `available_slots` offered — not built from the date and a
  /// string, so it is exactly the instant the database will check.
  DateTime? _slot;
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
                    service: _service,
                    selectedDate: _date,
                    selectedSlot: _slot,
                    onDateSelected: (d) => setState(() {
                      _date = d;
                      _slot = null;
                    }),
                    onSlotSelected: (s) => setState(() {
                      _slot = s;
                      _step = 3;
                    }),
                  ),
                _ => _ConfirmStep(
                    service: _service,
                    doctor: _doctor,
                    slot: _slot,
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
    final slot = _slot;
    if (service == null || doctor == null || slot == null) return;

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

    // The app only opens once this account holds a chart at the current
    // clinic, so this guards a stale session rather than a normal path —
    // without a chart there is no patient_id to book against.
    if (patient == null) {
      messenger.showSnackBar(const SnackBar(
        content: Text(
          'You have not joined this clinic yet. '
          'Join it from your profile with the clinic\'s code.',
        ),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    setState(() => _busy = true);
    try {
      await ref.read(appointmentsProvider.notifier).book(
            clinicId: clinicId,
            patientId: patient.id,
            doctorId: doctor.id,
            serviceId: service.id,
            serviceName: service.name,
            scheduledAt: slot,
          );
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(
        content: Text('Appointment requested. The clinic will confirm it.'),
        behavior: SnackBarBehavior.floating,
      ));
      context.goInClinic('/appointments');
    } catch (e) {
      // Most likely someone took the time first. Back to the list, which
      // is refetched without it.
      ref.invalidate(availableSlotsProvider);
      if (mounted) {
        setState(() {
          _slot = null;
          _step = 2;
        });
      }
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
              label: Text([
                s.name,
                '${s.durationMinutes} min',
                if (s.priceLabel != null) s.priceLabel!,
              ].join(' · ')),
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

class _DateTimeStep extends ConsumerWidget {
  const _DateTimeStep({
    required this.doctor,
    required this.service,
    required this.selectedDate,
    required this.selectedSlot,
    required this.onDateSelected,
    required this.onSlotSelected,
  });

  final Doctor? doctor;
  final Service? service;
  final DateTime? selectedDate;
  final DateTime? selectedSlot;
  final ValueChanged<DateTime> onDateSelected;
  final ValueChanged<DateTime> onSlotSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final doctor = this.doctor;
    final date = selectedDate;

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
            final today = DateUtils.dateOnly(DateTime.now());
            final picked = await showDatePicker(
              context: context,
              initialDate: _firstWorkingDay(today, doctor),
              firstDate: today,
              lastDate: today.add(const Duration(days: 60)),
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
            date == null
                ? 'Select date'
                : DateFormat('EEEE, MMMM d, y').format(date),
          ),
        ),
        if (date != null && doctor != null) ...[
          const SizedBox(height: 20),
          Text('Available times',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          AsyncView(
            value: ref.watch(availableSlotsProvider(
                (doctorId: doctor.id, day: date, serviceId: service?.id))),
            onRetry: () => ref.invalidate(availableSlotsProvider),
            builder: (slots) => slots.isEmpty
                ? Text(
                    'No times left on this day. Dr. ${doctor.name} may be '
                    'fully booked or away — try another date.',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  )
                : Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final slot in slots)
                        ChoiceChip(
                          label: Text(DateFormat.jm().format(slot)),
                          selected: slot == selectedSlot,
                          onSelected: (_) => onSlotSelected(slot),
                          selectedColor: cs.primaryContainer,
                        ),
                    ],
                  ),
          ),
        ],
      ],
    );
  }

  /// The date picker must open on a selectable day, or it throws.
  static DateTime _firstWorkingDay(DateTime today, Doctor? doctor) {
    final days = doctor?.availableWeekdays ?? const <int>[];
    for (var i = 1; i <= 7; i++) {
      final day = today.add(Duration(days: i));
      if (days.isEmpty || days.contains(day.weekday)) return day;
    }
    return today;
  }
}

class _ConfirmStep extends StatelessWidget {
  const _ConfirmStep({
    required this.service,
    required this.doctor,
    required this.slot,
    required this.busy,
    required this.onConfirm,
  });

  final Service? service;
  final Doctor? doctor;
  final DateTime? slot;
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
              _SummaryRow(label: 'Service', value: service?.name ?? ''),
              if (service?.priceLabel case final price?) ...[
                const Divider(height: 24),
                _SummaryRow(label: 'Price', value: price),
              ],
              const Divider(height: 24),
              _SummaryRow(
                  label: 'Doctor', value: 'Dr. ${doctor?.name ?? ''}'),
              const Divider(height: 24),
              _SummaryRow(
                  label: 'Specialty', value: doctor?.specialty ?? ''),
              const Divider(height: 24),
              _SummaryRow(
                label: 'Date',
                value: slot != null
                    ? DateFormat('EEEE, MMMM d, y').format(slot!)
                    : '',
              ),
              const Divider(height: 24),
              _SummaryRow(
                label: 'Time',
                value: slot != null
                    ? '${DateFormat.jm().format(slot!)} · '
                        '${service?.durationMinutes ?? 30} min'
                    : '',
              ),
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
