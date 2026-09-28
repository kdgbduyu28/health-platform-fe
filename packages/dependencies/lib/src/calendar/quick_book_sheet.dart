import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/appointment.dart';
import '../models/appointment_status.dart';
import '../models/doctor.dart';
import '../models/patient.dart';
import '../models/service.dart';
import '../models/time_off.dart';
import '../providers/appointments_provider.dart';
import '../providers/catalog_provider.dart';
import '../providers/clinic_provider.dart';
import '../widgets/async_view.dart';
import 'schedule_calendar.dart';

/// What stands in the way of booking [patientId] with [doctor] from [start]
/// for [minutes], judged from the visits already loaded. [blocking] ones the
/// database would refuse; [warnings] it allows staff to override (a time off
/// the doctor's grid, a walk-in squeezed in).
typedef BookingCheck = ({List<String> blocking, List<String> warnings});

BookingCheck checkBooking({
  required DateTime start,
  required int minutes,
  required Doctor doctor,
  required List<Appointment> appointments,
  required List<TimeOff> timeOff,
  String? patientId,
  String? patientName,
  DateTime? now,
}) {
  final end = start.add(Duration(minutes: minutes));
  final blocking = <String>[];
  final warnings = <String>[];
  bool overlaps(Appointment a) =>
      a.status.holdsTime && a.dateTime.isBefore(end) && a.endsAt.isAfter(start);
  String span(Appointment a) =>
      '${DateFormat('h:mm').format(a.dateTime)}–${DateFormat('h:mm a').format(a.endsAt)}';

  if (!start.isAfter(now ?? DateTime.now())) {
    blocking.add('That time has passed. For a visit that already happened, '
        'use "Manually add visit" on the patient\'s page.');
  }
  for (final a in appointments) {
    if (a.doctor.id == doctor.id && overlaps(a)) {
      blocking.add('Dr. ${doctor.name} already sees ${a.patient.name} ${span(a)}.');
    }
  }
  if (patientId != null) {
    for (final a in appointments) {
      if (a.patient.id == patientId && overlaps(a)) {
        blocking.add('${patientName ?? 'This patient'} already has a visit '
            '${span(a)} with Dr. ${a.doctor.name}.');
      }
    }
  }

  final closure = closureOn(timeOff, start);
  final leave = leaveOn(timeOff, doctor, start);
  if (closure != null) {
    warnings.add('The clinic is closed that day'
        '${closure.reason == null ? '' : ' (${closure.reason})'}.');
  } else if (leave != null) {
    warnings.add('Dr. ${doctor.name} is on leave that day'
        '${leave.reason == null ? '' : ' (${leave.reason})'}.');
  } else {
    final from = start.hour * 60 + start.minute;
    final to = from + minutes;
    final inHours = workingSpans(doctor, start, timeOff)
        .any((s) => s.start <= from && to <= s.end);
    if (!inHours) {
      warnings.add('Outside Dr. ${doctor.name}\'s hours '
          '(${formatWeekdays(doctor.availableWeekdays)}, '
          '${describeTimeSlots(doctor.availableTimeSlots)}).');
    }
  }
  return (blocking: blocking, warnings: warnings);
}

/// Books a visit from the calendar: the time and doctor come from where the
/// grid was tapped, and can still be changed. Returns whether it booked.
///
/// For a patient on file, or someone new registered with the booking. Staff
/// bookings go in confirmed. Clashes show as they are picked; the database
/// has the last word (a doctor or a patient in two places at once).
Future<bool> showQuickBookSheet(
  BuildContext context, {
  required DateTime start,
  Doctor? doctor,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final booked = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _QuickBookSheet(start: start, doctor: doctor),
  );
  if (booked == null) return false;
  messenger?.showSnackBar(SnackBar(
    content: Text(booked),
    behavior: SnackBarBehavior.floating,
  ));
  return true;
}

class _QuickBookSheet extends ConsumerStatefulWidget {
  const _QuickBookSheet({required this.start, this.doctor});

  final DateTime start;
  final Doctor? doctor;

  @override
  ConsumerState<_QuickBookSheet> createState() => _QuickBookSheetState();
}

class _QuickBookSheetState extends ConsumerState<_QuickBookSheet> {
  final _search = TextEditingController();
  final _newName = TextEditingController();
  final _newPhone = TextEditingController();

  Patient? _patient;
  bool _isNew = false;
  String _query = '';

  late DateTime _day = DateUtils.dateOnly(widget.start);
  late TimeOfDay _time = TimeOfDay.fromDateTime(widget.start);
  late String? _doctorId = widget.doctor?.id;
  Service? _service;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _search.dispose();
    _newName.dispose();
    _newPhone.dispose();
    super.dispose();
  }

  DateTime get _when =>
      DateTime(_day.year, _day.month, _day.day, _time.hour, _time.minute);

  bool get _hasPatient => _isNew
      ? _newName.text.trim().isNotEmpty && _newPhone.text.trim().isNotEmpty
      : _patient != null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final doctors = ref.watch(doctorsProvider).value ?? const <Doctor>[];
    final services = ref.watch(servicesProvider).value ?? const <Service>[];
    Doctor? doctor;
    for (final d in doctors) {
      if (d.id == _doctorId) doctor = d;
    }
    doctor ??= widget.doctor;

    final check = doctor == null
        ? null
        : checkBooking(
            start: _when,
            minutes: _service?.durationMinutes ?? 30,
            doctor: doctor,
            appointments: ref.watch(clinicAppointmentsProvider).value ?? const [],
            timeOff: ref.watch(timeOffProvider).value ?? const [],
            patientId: _isNew ? null : _patient?.id,
            patientName: _isNew ? null : _patient?.name,
          );
    final canSave = _hasPatient &&
        doctor != null &&
        _service != null &&
        (check?.blocking.isEmpty ?? false) &&
        !_busy;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: 20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('New appointment',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDay,
                    icon: const Icon(Icons.calendar_today),
                    label: Text(DateFormat('EEE, MMM d').format(_day)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickTime,
                    icon: const Icon(Icons.schedule),
                    label: Text(_time.format(context)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: doctors.any((d) => d.id == _doctorId) ? _doctorId : null,
              decoration: const InputDecoration(labelText: 'Doctor'),
              items: [
                for (final d in doctors)
                  DropdownMenuItem(value: d.id, child: Text('Dr. ${d.name}')),
              ],
              onChanged: (id) => setState(() => _doctorId = id),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _service?.id,
              decoration: InputDecoration(
                labelText: 'Service',
                helperText: _service == null
                    ? null
                    : 'Until ${DateFormat('h:mm a').format(_when.add(Duration(minutes: _service!.durationMinutes)))}',
              ),
              items: [
                for (final s in services)
                  DropdownMenuItem(
                    value: s.id,
                    child: Text('${s.name} · ${s.durationMinutes} min'),
                  ),
              ],
              onChanged: (id) =>
                  setState(() => _service = services.firstWhere((s) => s.id == id)),
            ),
            const SizedBox(height: 16),
            ..._patientPicker(cs),
            if (check != null) ...[
              for (final b in check.blocking)
                _Notice(text: b, icon: Icons.block, color: cs.error),
              for (final w in check.warnings)
                _Notice(text: w, icon: Icons.info_outline, color: cs.tertiary),
            ],
            if (_error != null) _Notice(text: _error!, icon: Icons.error_outline, color: cs.error),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: canSave ? () => _save(doctor!) : null,
              child: _busy
                  ? const SizedBox(
                      height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Book'),
            ),
          ],
        ),
      ),
    );
  }

  /// Search first: registering someone already on file splits their
  /// history in two.
  List<Widget> _patientPicker(ColorScheme cs) {
    final header = SegmentedButton<bool>(
      segments: const [
        ButtonSegment(
            value: false, icon: Icon(Icons.person_search_outlined), label: Text('On file')),
        ButtonSegment(
            value: true, icon: Icon(Icons.person_add_alt_outlined), label: Text('New patient')),
      ],
      selected: {_isNew},
      onSelectionChanged: (s) => setState(() => _isNew = s.first),
    );

    if (_isNew) {
      final phone = _newPhone.text.trim();
      final sameNumber = phone.replaceAll(RegExp(r'\D'), '').length < 7
          ? const <Patient>[]
          : [
              for (final p in ref.watch(patientSearchProvider(phone)).value ?? const <Patient>[])
                if (p.hasPhone(phone)) p,
            ];
      return [
        header,
        const SizedBox(height: 12),
        TextField(
          controller: _newName,
          onChanged: (_) => setState(() {}),
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
              labelText: 'Full Name', prefixIcon: Icon(Icons.person_outline)),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _newPhone,
          onChanged: (_) => setState(() {}),
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
              labelText: 'Phone Number', prefixIcon: Icon(Icons.phone_outlined)),
        ),
        for (final p in sameNumber)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.info_outline, color: cs.tertiary),
            title: Text('${p.name} is on file with this number'),
            trailing: FilledButton.tonal(
              onPressed: () => setState(() {
                _isNew = false;
                _patient = p;
              }),
              child: const Text('Use'),
            ),
          ),
      ];
    }

    final picked = _patient;
    if (picked != null) {
      return [
        header,
        const SizedBox(height: 12),
        Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            title: Text(picked.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(picked.phone),
            trailing: TextButton(
              onPressed: () => setState(() => _patient = null),
              child: const Text('Change'),
            ),
          ),
        ),
      ];
    }

    final query = _query.trim();
    final search = query.isEmpty ? null : ref.watch(patientSearchProvider(query));
    final matches = search?.value ?? const <Patient>[];
    return [
      header,
      const SizedBox(height: 12),
      TextField(
        controller: _search,
        onChanged: (v) => setState(() => _query = v),
        decoration: const InputDecoration(
            hintText: 'Search by name or phone…', prefixIcon: Icon(Icons.search)),
      ),
      if (search != null && !search.hasValue && !search.hasError)
        const LinearProgressIndicator(minHeight: 2)
      else if (search?.hasError ?? false)
        Text(describeError(search!.error!), style: TextStyle(color: cs.error))
      else if (query.isNotEmpty && matches.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text('No patient on file matches "$query".',
              style: TextStyle(color: cs.onSurfaceVariant)),
        )
      else
        for (final p in matches.take(5))
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(p.name),
            subtitle: Text(p.phone),
            onTap: () => setState(() {
              _patient = p;
              _query = '';
              _search.clear();
            }),
          ),
    ];
  }

  Future<void> _pickDay() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _day.isBefore(today) ? today : _day,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _day = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _save(Doctor doctor) async {
    final service = _service;
    final clinicId = ref.read(currentClinicIdProvider);
    if (service == null) return;
    if (clinicId == null) {
      setState(() => _error = 'Still loading the clinic. Try again in a moment.');
      return;
    }
    final when = _when;
    final patient = _isNew ? null : _patient;
    final name = patient?.name ?? _newName.text.trim();
    final notifier = ref.read(appointmentsProvider.notifier);

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (patient != null) {
        await notifier.book(
          clinicId: clinicId,
          patientId: patient.id,
          doctorId: doctor.id,
          serviceId: service.id,
          serviceName: service.name,
          scheduledAt: when,
          status: AppointmentStatus.confirmed,
        );
      } else {
        // One RPC, one transaction: no orphan chart if the time is lost.
        await notifier.bookWalkIn(
          clinicId: clinicId,
          fullName: name,
          phone: _newPhone.text.trim(),
          doctorId: doctor.id,
          serviceId: service.id,
          serviceName: service.name,
          scheduledAt: when,
        );
        invalidatePatientLists(ref);
      }
      ref.invalidate(availableSlotsProvider);
      if (mounted) {
        Navigator.pop(context,
            '$name booked with Dr. ${doctor.name}, ${DateFormat('EEE, MMM d · h:mm a').format(when)}');
      }
    } catch (e) {
      // Most likely someone took the time first: refetch, so the clash they
      // made shows above.
      if (mounted) setState(() => _error = describeError(e));
      await notifier.refresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.icon, required this.color});

  final String text;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: color))),
        ],
      ),
    );
  }
}
