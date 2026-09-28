import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/doctor.dart';
import '../models/patient.dart';
import '../models/service.dart';
import '../providers/appointments_provider.dart';
import '../providers/catalog_provider.dart';
import '../providers/clinic_provider.dart';
import '../providers/clinical_provider.dart';
import 'async_view.dart';

/// The fallback for a visit that happened but never went through the app —
/// nobody booked or checked it in on the day. The front desk and admins
/// enter it afterwards, for [patient] or, without one, for anyone on file or
/// someone new. Returns whether a visit was recorded.
///
/// A doctor's or admin's record goes in completed. The front desk's stays
/// confirmed for one of them to complete, since the database lets only
/// clinicians complete a visit. It may not overlap another visit of that
/// doctor's, and nobody is notified.
Future<bool> showRecordVisitSheet(BuildContext context, {Patient? patient}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final recorded = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _RecordVisitSheet(patient: patient),
  );
  if (recorded == null) return false;
  messenger?.showSnackBar(SnackBar(
    content: Text(recorded),
    behavior: SnackBarBehavior.floating,
  ));
  return true;
}

class _RecordVisitSheet extends ConsumerStatefulWidget {
  const _RecordVisitSheet({this.patient});

  final Patient? patient;

  @override
  ConsumerState<_RecordVisitSheet> createState() => _RecordVisitSheetState();
}

class _RecordVisitSheetState extends ConsumerState<_RecordVisitSheet> {
  final _search = TextEditingController();
  final _newName = TextEditingController();
  final _newPhone = TextEditingController();
  final _otherService = TextEditingController();

  late Patient? _patient = widget.patient;
  bool _isNew = false;
  String _query = '';

  // Usually the visit was earlier today: start there, at the last half hour.
  DateTime _day = DateUtils.dateOnly(DateTime.now());
  TimeOfDay _time = () {
    final now = TimeOfDay.now();
    return TimeOfDay(hour: now.hour, minute: now.minute < 30 ? 0 : 30);
  }();
  Doctor? _doctor;

  /// Null with [_isOther] set: a service not in the catalogue, named in
  /// [_otherService].
  Service? _service;
  bool _isOther = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _search.dispose();
    _newName.dispose();
    _newPhone.dispose();
    _otherService.dispose();
    super.dispose();
  }

  DateTime get _when =>
      DateTime(_day.year, _day.month, _day.day, _time.hour, _time.minute);

  String get _serviceName =>
      _isOther ? _otherService.text.trim() : (_service?.name ?? '');

  bool get _hasPatient => _isNew
      ? _newName.text.trim().isNotEmpty && _newPhone.text.trim().isNotEmpty
      : _patient != null;

  bool get _canSave =>
      _hasPatient && _doctor != null && _serviceName.isNotEmpty && !_busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
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
            Text('Manually add visit',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              'For a visit that happened but was never entered. Nobody is '
              'notified. It is saved as completed.',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            if (widget.patient == null) ...[
              ..._patientPicker(cs),
              const SizedBox(height: 16),
            ],
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDay,
                    icon: const Icon(Icons.calendar_today),
                    label: Text(DateUtils.isSameDay(_day, DateTime.now())
                        ? 'Today'
                        : DateFormat('MMM d, y').format(_day)),
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
            AsyncView(
              value: ref.watch(doctorsProvider),
              onRetry: () => ref.invalidate(doctorsProvider),
              builder: (doctors) => DropdownButtonFormField<String>(
                initialValue: _doctor?.id,
                decoration: const InputDecoration(labelText: 'Doctor'),
                items: [
                  for (final d in doctors)
                    DropdownMenuItem(value: d.id, child: Text('Dr. ${d.name}')),
                ],
                onChanged: (id) => setState(
                    () => _doctor = doctors.firstWhere((d) => d.id == id)),
              ),
            ),
            const SizedBox(height: 16),
            AsyncView(
              value: ref.watch(servicesProvider),
              onRetry: () => ref.invalidate(servicesProvider),
              builder: (services) => DropdownButtonFormField<String>(
                initialValue: _isOther ? '' : _service?.id,
                decoration: const InputDecoration(labelText: 'Service'),
                items: [
                  for (final s in services)
                    DropdownMenuItem(value: s.id, child: Text(s.name)),
                  const DropdownMenuItem(value: '', child: Text('Other…')),
                ],
                onChanged: (id) => setState(() {
                  _isOther = id == '';
                  _service =
                      _isOther ? null : services.firstWhere((s) => s.id == id);
                }),
              ),
            ),
            if (_isOther) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _otherService,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'What was done',
                  helperText: 'Counts as a 30-minute visit.',
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: cs.error)),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _canSave ? () => _save(true) : null,
              child: _busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Add visit'),
            ),
          ],
        ),
      ),
    );
  }

  /// Search first, as at the walk-in desk: registering someone already on
  /// file splits their history in two.
  List<Widget> _patientPicker(ColorScheme cs) {
    final picked = _patient;
    final header = SegmentedButton<bool>(
      segments: const [
        ButtonSegment(
          value: false,
          icon: Icon(Icons.person_search_outlined),
          label: Text('On file'),
        ),
        ButtonSegment(
          value: true,
          icon: Icon(Icons.person_add_alt_outlined),
          label: Text('New patient'),
        ),
      ],
      selected: {_isNew},
      onSelectionChanged: (s) => setState(() => _isNew = s.first),
    );

    if (_isNew) {
      final phone = _newPhone.text.trim();
      final sameNumber = phone.replaceAll(RegExp(r'\D'), '').length < 7
          ? const <Patient>[]
          : [
              for (final p in ref.watch(patientSearchProvider(phone)).value ??
                  const <Patient>[])
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
            labelText: 'Full Name',
            prefixIcon: Icon(Icons.person_outline),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _newPhone,
          onChanged: (_) => setState(() {}),
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Phone Number',
            prefixIcon: Icon(Icons.phone_outlined),
          ),
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

    if (picked != null) {
      return [
        header,
        const SizedBox(height: 12),
        Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            title: Text(picked.name,
                style: const TextStyle(fontWeight: FontWeight.w600)),
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
          hintText: 'Search by name or phone…',
          prefixIcon: Icon(Icons.search),
        ),
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
      initialDate: _day,
      firstDate: DateTime(today.year - 5),
      lastDate: today,
      helpText: 'When was the visit?',
    );
    if (picked != null) setState(() => _day = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _save(bool complete) async {
    final when = _when;
    final doctor = _doctor;
    if (doctor == null) return;
    if (when.isAfter(DateTime.now())) {
      setState(() => _error = 'That time has not come yet. Book it instead.');
      return;
    }
    final clinicId = ref.read(currentClinicIdProvider);
    if (clinicId == null) {
      setState(() => _error = 'Still loading the clinic. Try again in a moment.');
      return;
    }

    final patient = _isNew ? null : _patient;
    final name = patient?.name ?? _newName.text.trim();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(appointmentsProvider.notifier).recordMissedVisit(
            clinicId: clinicId,
            patientId: patient?.id,
            newPatientName: _isNew ? name : null,
            newPatientPhone: _isNew ? _newPhone.text.trim() : null,
            doctorId: doctor.id,
            serviceId: _isOther ? null : _service?.id,
            serviceName: _serviceName,
            scheduledAt: when,
            complete: complete,
          );
      if (patient != null) ref.invalidate(patientHistoryProvider(patient.id));
      if (_isNew) invalidatePatientLists(ref);
      if (mounted) {
        Navigator.pop(context,
            'Visit on ${DateFormat('MMM d · h:mm a').format(when)} recorded for $name');
      }
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
