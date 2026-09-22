import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:api_sdk/api_sdk.dart';

/// `/:clinic/settings/doctors` — the roster, and each doctor's working week.
///
/// What a doctor can be booked for comes from here: their weekdays and the
/// start times on each (see `public.available_slots`). Doctors are
/// deactivated rather than removed; their past visits still point at them.
class DoctorsScreen extends ConsumerWidget {
  const DoctorsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roster = ref.watch(rosterProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Doctors')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, ref, null),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Add doctor'),
      ),
      body: AsyncView(
        value: roster,
        onRetry: () => ref.invalidate(rosterProvider),
        builder: (doctors) => doctors.isEmpty
            ? const _Empty(
                'No doctors yet. Add one so patients have someone to book.')
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                itemCount: doctors.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final d = doctors[i];
                  final cs = Theme.of(context).colorScheme;
                  return Card(
                    child: ListTile(
                      onTap: () => _edit(context, ref, d),
                      leading: DoctorAvatar(doctor: d),
                      title: Text('Dr. ${d.name}',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: d.isActive ? null : cs.outline,
                          )),
                      subtitle: Text([
                        if (d.specialty.isNotEmpty) d.specialty,
                        d.availableWeekdays.isEmpty
                            ? 'No working days'
                            : formatWeekdays(d.availableWeekdays),
                        describeTimeSlots(d.availableTimeSlots),
                      ].join('\n')),
                      isThreeLine: true,
                      trailing: d.isActive
                          ? const Icon(Icons.edit_outlined)
                          : const Chip(label: Text('Inactive')),
                    ),
                  );
                },
              ),
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, Doctor? doctor) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _DoctorEditor(doctor: doctor),
    );
    if (saved == true) invalidateCatalog(ref);
  }
}

class _DoctorEditor extends ConsumerStatefulWidget {
  const _DoctorEditor({this.doctor});

  /// Null to add a new one.
  final Doctor? doctor;

  @override
  ConsumerState<_DoctorEditor> createState() => _DoctorEditorState();
}

class _DoctorEditorState extends ConsumerState<_DoctorEditor> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.doctor?.name);
  late final _specialty = TextEditingController(text: widget.doctor?.specialty);
  late Set<int> _weekdays = {...?widget.doctor?.availableWeekdays};
  late bool _active = widget.doctor?.isActive ?? true;

  /// The hours as first time / last time / every N minutes. Starts from the
  /// doctor's current times when they fit that shape.
  late WorkingHours _hours;

  /// The doctor's current times do not fit a first/last/step pattern (a
  /// lunch break, say). They are kept unless the admin edits the hours.
  late bool _keepIrregular;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final slots = widget.doctor?.availableTimeSlots ?? const <String>[];
    final pattern = workingHoursOf(slots);
    _keepIrregular = slots.isNotEmpty && pattern == null;
    _hours = pattern ?? (first: 9 * 60, last: 16 * 60 + 30, step: 30);
    if (widget.doctor == null) _weekdays = {1, 2, 3, 4, 5};
  }

  @override
  void dispose() {
    _name.dispose();
    _specialty.dispose();
    super.dispose();
  }

  List<String> get _slots => _keepIrregular
      ? widget.doctor!.availableTimeSlots
      : generateTimeSlots(_hours);

  Future<void> _pickTime({required bool first}) async {
    final current = first ? _hours.first : _hours.last;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
    );
    if (picked == null) return;
    final m = picked.hour * 60 + picked.minute;
    setState(() {
      _keepIrregular = false;
      _hours = first
          ? (first: m, last: _hours.last < m ? m : _hours.last, step: _hours.step)
          : (first: _hours.first > m ? m : _hours.first, last: m, step: _hours.step);
    });
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    if (_weekdays.isEmpty && _active) {
      setState(() => _error = 'Pick at least one working day.');
      return;
    }
    final slots = _slots;
    if (slots.isEmpty && _active) {
      setState(() => _error = 'Set at least one start time.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final repo = ref.read(healthRepositoryProvider);
    final weekdays = _weekdays.toList()..sort();
    try {
      final doctor = widget.doctor;
      if (doctor == null) {
        await repo.addDoctor(
          clinicId: ref.read(currentClinicIdProvider)!,
          name: _name.text.trim(),
          specialty: _specialty.text.trim(),
          weekdays: weekdays,
          timeSlots: slots,
        );
      } else {
        await repo.updateDoctor(doctor.id, {
          'full_name': _name.text.trim(),
          'specialty': _specialty.text.trim(),
          'available_weekdays': weekdays,
          'available_time_slots': slots,
          'is_active': _active,
        });
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isNew = widget.doctor == null;
    const dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    return AlertDialog(
      title: Text(isNew ? 'Add doctor' : 'Edit Dr. ${widget.doctor!.name}'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _name,
                  autofocus: isNew,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Full name',
                    hintText: 'Maria Santos (no "Dr.")',
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _specialty,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Specialty'),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Enter a specialty'
                      : null,
                ),
                const SizedBox(height: 20),
                Text('Working days', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (var d = 1; d <= 7; d++)
                      FilterChip(
                        label: Text(dayNames[d - 1]),
                        selected: _weekdays.contains(d),
                        onSelected: (on) => setState(() {
                          on ? _weekdays.add(d) : _weekdays.remove(d);
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                Text('Hours', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                if (_keepIrregular) ...[
                  Text(
                    'Keeps the current ${widget.doctor!.availableTimeSlots.length} '
                    'start times (${widget.doctor!.availableTimeSlots.join(', ')}). '
                    'Change the hours below to replace them with an even '
                    'schedule.',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                ],
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _pickTime(first: true),
                        child: Text('First ${formatClock(_hours.first)}'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _pickTime(first: false),
                        child: Text('Last ${formatClock(_hours.last)}'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  initialValue: const [10, 15, 20, 30, 45, 60].contains(_hours.step)
                      ? _hours.step
                      : 30,
                  decoration: const InputDecoration(labelText: 'Every'),
                  items: [
                    for (final m in const [10, 15, 20, 30, 45, 60])
                      DropdownMenuItem(value: m, child: Text('$m minutes')),
                  ],
                  onChanged: (m) => setState(() {
                    _keepIrregular = false;
                    _hours = (first: _hours.first, last: _hours.last, step: m!);
                  }),
                ),
                const SizedBox(height: 8),
                Text(
                  '${_slots.length} start times a day. The last start time is '
                  'the latest a visit can begin; longer services only fit '
                  'where the doctor is free for their whole length.',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                ),
                if (!isNew) ...[
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Taking bookings'),
                    subtitle: const Text(
                        'Off hides this doctor from booking. Visits already '
                        'booked stay booked.'),
                    value: _active,
                    onChanged: (v) => setState(() => _active = v),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: cs.error)),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
          onPressed: _busy ? null : _save,
          child: Text(isNew ? 'Add' : 'Save'),
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(text, textAlign: TextAlign.center),
        ),
      );
}
