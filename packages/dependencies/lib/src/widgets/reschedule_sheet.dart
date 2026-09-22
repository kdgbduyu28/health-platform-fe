import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/appointment.dart';
import '../models/appointment_status.dart';
import '../models/doctor.dart';
import '../providers/appointments_provider.dart';
import '../providers/catalog_provider.dart';
import 'async_view.dart';

/// Moves [appointment] to a new time, and says how it went. Returns whether
/// it moved.
///
/// A patient picks from the times the clinic offers, and learns the clinic
/// must confirm again. Staff ([staff]) may also switch the doctor, or set a
/// time off the grid — the database still refuses an overlap.
Future<bool> showRescheduleSheet(
  BuildContext context,
  Appointment appointment, {
  required bool staff,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final moved = await showModalBottomSheet<DateTime>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _RescheduleSheet(appointment: appointment, staff: staff),
  );
  if (moved == null) return false;
  final when = DateFormat('EEE, MMM d · h:mm a').format(moved);
  messenger?.showSnackBar(SnackBar(
    content: Text(staff
        ? 'Moved to $when'
        : 'Moved to $when. The clinic will confirm the new time.'),
    behavior: SnackBarBehavior.floating,
  ));
  return true;
}

class _RescheduleSheet extends ConsumerStatefulWidget {
  const _RescheduleSheet({required this.appointment, required this.staff});

  final Appointment appointment;
  final bool staff;

  @override
  ConsumerState<_RescheduleSheet> createState() => _RescheduleSheetState();
}

class _RescheduleSheetState extends ConsumerState<_RescheduleSheet> {
  late Doctor _doctor = widget.appointment.doctor;
  DateTime? _day;
  DateTime? _slot;
  bool _busy = false;
  String? _error;

  Appointment get _a => widget.appointment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final day = _day;

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
            Text('Move this visit',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              '${_a.service} · now ${DateFormat('EEE, MMM d · h:mm a').format(_a.dateTime)}',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            if (!widget.staff && _a.status == AppointmentStatus.confirmed) ...[
              const SizedBox(height: 8),
              Text(
                'Your visit is confirmed. A new time goes back to the clinic '
                'to confirm.',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
              ),
            ],
            if (widget.staff) ...[
              const SizedBox(height: 16),
              AsyncView(
                value: ref.watch(doctorsProvider),
                onRetry: () => ref.invalidate(doctorsProvider),
                builder: (doctors) => DropdownButtonFormField<String>(
                  initialValue: _doctor.id,
                  decoration: const InputDecoration(labelText: 'Doctor'),
                  items: [
                    for (final d in {
                      _a.doctor.id: _a.doctor,
                      for (final d in doctors) d.id: d,
                    }.values)
                      DropdownMenuItem(value: d.id, child: Text('Dr. ${d.name}')),
                  ],
                  onChanged: (id) => setState(() {
                    _doctor = doctors.firstWhere((d) => d.id == id,
                        orElse: () => _a.doctor);
                    _slot = null;
                  }),
                ),
              ),
            ],
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _pickDay,
              icon: const Icon(Icons.calendar_today),
              label: Text(day == null
                  ? 'Pick a day'
                  : DateFormat('EEEE, MMMM d, y').format(day)),
            ),
            if (day != null) ...[
              const SizedBox(height: 16),
              AsyncView(
                value: ref.watch(availableSlotsProvider((
                  doctorId: _doctor.id,
                  day: day,
                  serviceId: _a.serviceId,
                  ignore: _a.id,
                ))),
                onRetry: () => ref.invalidate(availableSlotsProvider),
                builder: (slots) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (slots.isEmpty)
                      Text(
                        'No times left on this day. Dr. ${_doctor.name} may '
                        'be fully booked or away — try another day.',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final s in slots)
                            ChoiceChip(
                              label: Text(DateFormat.jm().format(s)),
                              selected: s == _slot,
                              onSelected: (_) => setState(() => _slot = s),
                            ),
                        ],
                      ),
                    if (widget.staff) ...[
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: _pickOffGridTime,
                        icon: const Icon(Icons.more_time, size: 18),
                        label: Text(_slot != null && !slots.contains(_slot)
                            ? 'Other time: ${DateFormat.jm().format(_slot!)}'
                            : 'Other time…'),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: cs.error)),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _slot == null || _busy ? null : _save,
              child: _busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(_slot == null
                      ? 'Pick a new time'
                      : 'Move to ${DateFormat('EEE, MMM d · h:mm a').format(_slot!)}'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDay() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final weekdays = _doctor.availableWeekdays;
    // Staff may book any day; a patient only the doctor's working days.
    bool selectable(DateTime d) =>
        widget.staff || weekdays.isEmpty || weekdays.contains(d.weekday);
    var initial = _day ?? today;
    for (var i = 0; i < 14 && !selectable(initial); i++) {
      initial = initial.add(const Duration(days: 1));
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: selectable(initial) ? initial : today,
      firstDate: today,
      lastDate: today.add(const Duration(days: 90)),
      selectableDayPredicate: selectable,
    );
    if (picked != null) {
      setState(() {
        _day = picked;
        _slot = null;
        _error = null;
      });
    }
  }

  Future<void> _pickOffGridTime() async {
    final day = _day;
    if (day == null) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_slot ?? _a.dateTime),
    );
    if (t == null) return;
    setState(() {
      _slot = DateTime(day.year, day.month, day.day, t.hour, t.minute);
      _error = null;
    });
  }

  Future<void> _save() async {
    final slot = _slot;
    if (slot == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(appointmentsProvider.notifier).reschedule(
            _a.id,
            slot,
            doctorId: _doctor.id == _a.doctor.id ? null : _doctor.id,
          );
      ref.invalidate(availableSlotsProvider);
      if (mounted) Navigator.pop(context, slot);
    } catch (e) {
      // Most likely someone took the time first; the list refetches without it.
      ref.invalidate(availableSlotsProvider);
      if (mounted) {
        setState(() {
          _error = describeError(e);
          _slot = null;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
