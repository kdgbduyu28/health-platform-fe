import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:api_sdk/api_sdk.dart';

enum _PatientMode { existing, newPatient }

class WalkInBookingScreen extends ConsumerStatefulWidget {
  const WalkInBookingScreen({super.key, this.initialPatientId});

  /// Preselects a patient already on file — set when booking from their
  /// history page.
  final String? initialPatientId;

  @override
  ConsumerState<WalkInBookingScreen> createState() =>
      _WalkInBookingScreenState();
}

class _WalkInBookingScreenState extends ConsumerState<WalkInBookingScreen> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  // Search first. book_walk_in always registers a NEW person and chart, so
  // registering someone already on file splits their history in two.
  _PatientMode _mode = _PatientMode.existing;
  String? _patientId;
  String _query = '';

  Service? _service;
  Doctor? _doctor;
  /// One of today's times `available_slots` offered.
  DateTime? _slot;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _patientId = widget.initialPatientId;
  }

  @override
  void didUpdateWidget(WalkInBookingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The tab keeps its state, so arriving from another patient's history
    // page updates the widget rather than creating a new one.
    final id = widget.initialPatientId;
    if (id != null && id != oldWidget.initialPatientId) {
      _mode = _PatientMode.existing;
      _patientId = id;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  /// The chart picked, fetched by id: it may be anyone at the clinic, not
  /// only someone in the current search results.
  Patient? _selected(WidgetRef ref) {
    final id = _patientId;
    return id == null ? null : ref.watch(patientByIdProvider(id)).value;
  }

  @override
  Widget build(BuildContext context) {
    final doctors = ref.watch(doctorsProvider).value ?? const <Doctor>[];
    final services = ref.watch(servicesProvider).value ?? const <Service>[];
    final selected = _selected(ref);
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    final who = <Widget>[
      // Patient
      Text('Patient',
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      SegmentedButton<_PatientMode>(
        segments: const [
          ButtonSegment(
            value: _PatientMode.existing,
            icon: Icon(Icons.person_search_outlined),
            label: Text('On file'),
          ),
          ButtonSegment(
            value: _PatientMode.newPatient,
            icon: Icon(Icons.person_add_alt_outlined),
            label: Text('New patient'),
          ),
        ],
        selected: {_mode},
        onSelectionChanged: (s) => setState(() => _mode = s.first),
      ),
      const SizedBox(height: 12),
      if (_mode == _PatientMode.existing)
        ..._existingPatient(selected, cs)
      else
        ..._newPatient(cs),
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
          final isSelected = s.id == _service?.id;
          return FilterChip(
            label: Text(s.name),
            selected: isSelected,
            onSelected: (_) => setState(() {
              _service = s;
              _slot = null;
            }),
            selectedColor: cs.primaryContainer,
            checkmarkColor: cs.onPrimaryContainer,
          );
        }).toList(),
      ),
      const SizedBox(height: 24),

    ];
    final when = <Widget>[
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
                onTap: () => setState(() {
                  _doctor = d;
                  _slot = null;
                }),
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

      // Today's free times for this doctor and service.
      Text('Time',
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      if (_doctor case final doctor?)
        AsyncView(
          value: ref.watch(availableSlotsProvider((
            doctorId: doctor.id,
            // Date only: a raw now() is a new family key on every build, so
            // each fetch's result rebuilt the screen and started another.
            day: DateUtils.dateOnly(DateTime.now()),
            serviceId: _service?.id,
            ignore: null,
          ))),
          onRetry: () => ref.invalidate(availableSlotsProvider),
          builder: (slots) => slots.isEmpty
              ? Text(
                  'Dr. ${doctor.name} has no free time left today.',
                  style: TextStyle(color: cs.onSurfaceVariant),
                )
              : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final slot in slots)
                      ChoiceChip(
                        label: Text(DateFormat.jm().format(slot)),
                        selected: slot == _slot,
                        onSelected: (_) => setState(() => _slot = slot),
                        selectedColor: cs.primaryContainer,
                      ),
                  ],
                ),
        )
      else
        Text('Choose a doctor to see their free times.',
            style: TextStyle(color: cs.onSurfaceVariant)),
      const SizedBox(height: 32),

    ];
    final book = FilledButton.icon(
      onPressed: (_canSubmit(selected) && !_busy)
          ? () => _submit(context)
          : null,
      icon: _busy
          ? const SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.add_circle_outline),
      label: const Text('Book Walk-In Appointment'),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Walk-In Booking')),
      body: Form(
        key: _formKey,
        child: CenteredScroll(
          // Two steps side by side on a tablet held sideways: who and what
          // on the left, with whom and when on the right, next to Book.
          maxWidth: ContentWidth.detail,
          padding: const EdgeInsets.all(16),
          builder: (padding) => ListView(
            padding: padding,
            children: [
              SplitColumns(
                narrow: [...who, ...when, book],
                start: who,
                end: [...when, book],
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _existingPatient(Patient? selected, ColorScheme cs) {
    if (selected != null) {
      return [
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: cs.primary, width: 2),
          ),
          child: ListTile(
            leading: _Initials(patient: selected),
            title: Text(selected.name,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(selected.phone),
            trailing: TextButton(
              onPressed: () => setState(() => _patientId = null),
              child: const Text('Change'),
            ),
          ),
        ),
      ];
    }

    final query = _query.trim();
    // Searched in the database, a moment after typing stops.
    final search = query.isEmpty ? null : ref.watch(patientSearchProvider(query));
    final matches = search?.value ?? const <Patient>[];
    final searching = search != null && !search.hasValue && !search.hasError;

    return [
      TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _query = v),
        decoration: const InputDecoration(
          hintText: 'Search by name or phone…',
          prefixIcon: Icon(Icons.search),
        ),
      ),
      const SizedBox(height: 8),
      if (query.isEmpty)
        Text('Find the patient first. Register them as new only if they are '
            'not on file.',
            style: TextStyle(color: cs.outline, fontSize: 13))
      else if (searching)
        const LinearProgressIndicator(minHeight: 2)
      else if (search?.hasError ?? false)
        Text(describeError(search!.error!), style: TextStyle(color: cs.error))
      else if (matches.isEmpty) ...[
        Text('No patient on file matches "$query".',
            style: TextStyle(color: cs.onSurfaceVariant)),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() {
              // Carry what was typed over, so it is not typed twice.
              final looksLikePhone = RegExp(r'^[\d\s+()-]+$').hasMatch(query);
              (looksLikePhone ? _phoneCtrl : _nameCtrl).text = query;
              _mode = _PatientMode.newPatient;
            }),
            icon: const Icon(Icons.person_add_alt_outlined, size: 18),
            label: const Text('Register as a new patient'),
          ),
        ),
      ] else
        ...matches.map((p) => Card(
              child: ListTile(
                leading: _Initials(patient: p),
                title: Text(p.name,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(p.phone),
                onTap: () => setState(() {
                  _patientId = p.id;
                  _query = '';
                  _searchCtrl.clear();
                }),
              ),
            )),
    ];
  }

  List<Widget> _newPatient(ColorScheme cs) {
    // Once a full number is typed, look it up: a "new" walk-in is often
    // already on file.
    final phone = _phoneCtrl.text.trim();
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    final sameNumber = digits.length < 7
        ? const <Patient>[]
        : [
            for (final p in ref.watch(patientSearchProvider(phone)).value ??
                const <Patient>[])
              if (p.hasPhone(phone)) p,
          ];

    return [
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
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(
          labelText: 'Phone Number',
          prefixIcon: Icon(Icons.phone_outlined),
        ),
        keyboardType: TextInputType.phone,
        validator: (v) =>
            v == null || v.trim().isEmpty ? 'Phone is required' : null,
      ),
      if (sameNumber.isNotEmpty) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.tertiaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Already on file with this number',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: cs.onTertiaryContainer)),
              for (final p in sameNumber)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(p.name,
                      style: TextStyle(color: cs.onTertiaryContainer)),
                  subtitle: Text(p.phone,
                      style: TextStyle(color: cs.onTertiaryContainer)),
                  trailing: FilledButton.tonal(
                    onPressed: () => setState(() {
                      _mode = _PatientMode.existing;
                      _patientId = p.id;
                    }),
                    child: const Text('Use'),
                  ),
                ),
            ],
          ),
        ),
      ],
    ];
  }

  bool _canSubmit(Patient? selected) =>
      _service != null &&
      _doctor != null &&
      _slot != null &&
      (_mode == _PatientMode.newPatient || selected != null);

  Future<void> _submit(BuildContext context) async {
    final isNew = _mode == _PatientMode.newPatient;
    if (isNew && !_formKey.currentState!.validate()) return;
    final service = _service;
    final doctor = _doctor;
    final slot = _slot;
    final id = _patientId;
    final patient =
        isNew || id == null ? null : ref.read(patientByIdProvider(id)).value;
    if (service == null || doctor == null || slot == null) return;
    if (!isNew && patient == null) return;

    final messenger = ScaffoldMessenger.of(context);
    final clinicId = ref.read(currentClinicIdProvider);
    if (clinicId == null) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Still loading the clinic. Try again in a moment.'),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    final scheduledAt = slot;
    final notifier = ref.read(appointmentsProvider.notifier);
    final name = patient?.name ?? _nameCtrl.text.trim();

    setState(() => _busy = true);
    try {
      if (patient != null) {
        await notifier.book(
          clinicId: clinicId,
          patientId: patient.id,
          doctorId: doctor.id,
          serviceId: service.id,
          serviceName: service.name,
          scheduledAt: scheduledAt,
          status: AppointmentStatus.confirmed,
        );
      } else {
        // One RPC, one transaction. Registering the chart and booking against
        // it as two separate client writes left an orphan patient behind
        // whenever the booking lost the double-booking race.
        await notifier.bookWalkIn(
          clinicId: clinicId,
          fullName: name,
          phone: _phoneCtrl.text.trim(),
          doctorId: doctor.id,
          serviceId: service.id,
          serviceName: service.name,
          scheduledAt: scheduledAt,
        );
        invalidatePatientLists(ref);
      }

      if (!context.mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Booked!'),
          content: Text(
            '$name is booked for ${service.name} at '
            '${DateFormat('h:mm a').format(scheduledAt)} '
            'with Dr. ${doctor.name}.',
          ),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                _reset();
                context.goInClinic('/check-in');
              },
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } catch (e) {
      // Most likely the time was taken meanwhile: refetch, and pick again.
      ref.invalidate(availableSlotsProvider);
      if (mounted) setState(() => _slot = null);
      messenger.showSnackBar(SnackBar(
        content: Text(describeError(e)),
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The tab keeps its state between visits; the next walk-in starts clean.
  void _reset() {
    setState(() {
      _mode = _PatientMode.existing;
      _patientId = null;
      _query = '';
      _service = null;
      _doctor = null;
      _slot = null;
    });
    _searchCtrl.clear();
    _nameCtrl.clear();
    _phoneCtrl.clear();
  }
}

class _Initials extends StatelessWidget {
  const _Initials({required this.patient});
  final Patient patient;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return CircleAvatar(
      backgroundColor: cs.primaryContainer,
      child: Text(patient.initials,
          style: TextStyle(
              color: cs.onPrimaryContainer, fontWeight: FontWeight.bold)),
    );
  }
}
