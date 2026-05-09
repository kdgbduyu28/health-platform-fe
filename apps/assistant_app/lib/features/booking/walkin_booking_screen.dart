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

  String? _service;
  Doctor? _doctor;
  String? _timeSlot;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final clinicType = ref.watch(clinicTypeProvider);
    final doctors =
        MockData.doctors.where((d) => d.clinicType == clinicType).toList();
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
              children: clinicType.services.map((s) {
                final selected = s == _service;
                return FilterChip(
                  label: Text(s),
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
              onPressed: _canSubmit() ? () => _submit(context) : null,
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('Book Walk-In Appointment'),
            ),
          ],
        ),
      ),
    );
  }

  bool _canSubmit() =>
      _service != null && _doctor != null && _timeSlot != null;

  void _submit(BuildContext context) {
    if (!_formKey.currentState!.validate()) return;
    if (!_canSubmit()) return;

    final parts = _timeSlot!.split(':');
    final now = DateTime.now();
    final dateTime = DateTime(
        now.year, now.month, now.day, int.parse(parts[0]), int.parse(parts[1]));

    final patient = Patient(
      id: 'walk_${DateTime.now().millisecondsSinceEpoch}',
      name: _nameCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
      email: '',
    );

    final appointment = Appointment(
      id: 'w_${DateTime.now().millisecondsSinceEpoch}',
      patient: patient,
      doctor: _doctor!,
      dateTime: dateTime,
      service: _service!,
      status: AppointmentStatus.confirmed,
      clinicType: ref.read(clinicTypeProvider),
    );

    ref.read(appointmentsProvider.notifier).add(appointment);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Booked!'),
        content: Text(
          '${patient.name} is booked for $_service at ${DateFormat('h:mm a').format(dateTime)} with Dr. ${_doctor!.name}.',
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
  }
}
