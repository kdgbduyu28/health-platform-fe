import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:api_sdk/api_sdk.dart';

class WalkInBookingScreen extends ConsumerStatefulWidget {
  const WalkInBookingScreen({super.key});

  @override
  ConsumerState<WalkInBookingScreen> createState() =>
      _WalkInBookingScreenState();
}

class _WalkInBookingScreenState extends ConsumerState<WalkInBookingScreen> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  Service? _service;
  Doctor? _doctor;
  String? _timeSlot;
  bool _busy = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final doctors = ref.watch(doctorsProvider).value ?? const <Doctor>[];
    final services = ref.watch(servicesProvider).value ?? const <Service>[];
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Walk-In Booking')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Patient info
            Text('Patient Information',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Full Name',
                prefixIcon: Icon(Icons.person_outline),
              ),
              textCapitalization: TextCapitalization.words,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Name is required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phoneCtrl,
              decoration: const InputDecoration(
                labelText: 'Phone Number',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
              keyboardType: TextInputType.phone,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Phone is required' : null,
            ),
            const SizedBox(height: 24),

            // Service
            Text('Service',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: services.map((s) {
                final selected = s.id == _service?.id;
                return FilterChip(
                  label: Text(s.name),
                  selected: selected,
                  onSelected: (_) => setState(() => _service = s),
                  selectedColor: cs.primaryContainer,
                  checkmarkColor: cs.onPrimaryContainer,
                );
              }).toList(),
            ),
            const SizedBox(height: 24),

            // Doctor
            Text('Doctor',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ...doctors.map((d) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: _doctor?.id == d.id
                            ? cs.primary
                            : cs.outlineVariant,
                        width: _doctor?.id == d.id ? 2 : 1,
                      ),
                    ),
                    child: ListTile(
                      onTap: () => setState(() => _doctor = d),
                      leading: DoctorAvatar(doctor: d),
                      title: Text('Dr. ${d.name}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w600)),
                      subtitle: Text(d.specialty),
                      trailing: _doctor?.id == d.id
                          ? Icon(Icons.check_circle, color: cs.primary)
                          : null,
                    ),
                  ),
                )),
            const SizedBox(height: 24),

            // Time slot (today's available slots)
            Text('Time Slot',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: (_doctor?.availableTimeSlots ?? []).map((s) {
                final selected = s == _timeSlot;
                return ChoiceChip(
                  label: Text(s),
                  selected: selected,
                  onSelected: (_) => setState(() => _timeSlot = s),
                  selectedColor: cs.primaryContainer,
                );
              }).toList(),
            ),
            const SizedBox(height: 32),

            // Book button
            FilledButton.icon(
              onPressed:
                  (_canSubmit() && !_busy) ? () => _submit(context) : null,
              icon: _busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_circle_outline),
              label: const Text('Book Walk-In Appointment'),
            ),
          ],
        ),
      ),
    );
  }

  bool _canSubmit() =>
      _service != null && _doctor != null && _timeSlot != null;

  Future<void> _submit(BuildContext context) async {
    if (!_formKey.currentState!.validate()) return;
    final service = _service;
    final doctor = _doctor;
    final slot = _timeSlot;
    if (service == null || doctor == null || slot == null) return;

    final messenger = ScaffoldMessenger.of(context);
    final clinicId = ref.read(currentClinicIdProvider);
    if (clinicId == null) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Still loading the clinic. Try again in a moment.'),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    final parts = slot.split(':');
    final now = DateTime.now();
    final scheduledAt = DateTime(
        now.year, now.month, now.day, int.parse(parts[0]), int.parse(parts[1]));

    setState(() => _busy = true);
    try {
      // Register the chart first, then book against it. The patient row is
      // stamped with this clinic, which is exactly what lets RLS hand the row
      // straight back to us — an appointment-only visibility rule would make
      // the record we just created unreadable.
      //
      // Known gap: these are two statements, not one transaction. If the
      // booking loses the double-booking race the patient record survives
      // without an appointment. Folding both into a Postgres function called
      // over RPC would make it atomic.
      final patient =
          await ref.read(healthRepositoryProvider).createWalkInPatient(
                clinicId: clinicId,
                fullName: _nameCtrl.text.trim(),
                phone: _phoneCtrl.text.trim(),
              );

      // Staff may book straight to confirmed; RLS only forces 'pending' on
      // bookings made by patients themselves.
      await ref.read(appointmentsProvider.notifier).book(
            clinicId: clinicId,
            patientId: patient.id,
            doctorId: doctor.id,
            serviceId: service.id,
            serviceName: service.name,
            scheduledAt: scheduledAt,
            status: AppointmentStatus.confirmed,
          );

      if (!context.mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Booked!'),
          content: Text(
            '${patient.name} is booked for ${service.name} at '
            '${DateFormat('h:mm a').format(scheduledAt)} '
            'with Dr. ${doctor.name}.',
          ),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                context.go('/');
              },
              child: const Text('Done'),
            ),
          ],
        ),
      );
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
