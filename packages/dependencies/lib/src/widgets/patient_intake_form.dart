import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/patient.dart';
import '../models/patient_intake.dart';
import 'async_view.dart';

/// Who is holding the device, which decides the wording: "your birthday" for
/// the patient, "the patient's birthday" for the front desk.
enum IntakeAudience { patient, staff }

/// The patient information form, four steps: about you, contact, health, and
/// consent. The same form everywhere — the front desk typing it in, the
/// patient on the front desk tablet, the patient in the patient app — so a
/// clinic gets the same answers however they arrive.
///
/// Built for a tablet held by someone who has never seen the app: one topic
/// per step, big targets, and nothing but Back and Next to find. Fills the
/// space it is given; the caller supplies the Scaffold around it.
///
/// [patient] and [intake] prefill it (an existing chart, or a signed-up
/// patient's name and email). Consent is never prefilled: whoever saves the
/// form agrees again.
///
/// Optionally a parent or guardian answers for the patient (a child, or an
/// adult who cannot answer for themself): they give their own details first,
/// the questions then ask about "the patient", and they sign.
class PatientIntakeForm extends StatefulWidget {
  const PatientIntakeForm({
    super.key,
    required this.audience,
    required this.clinicName,
    required this.isDental,
    required this.onSubmit,
    this.patient,
    this.intake,
    this.submitLabel = 'Submit',
  });

  final IntakeAudience audience;
  final String clinicName;

  /// Adds the dental questions (last dental visit).
  final bool isDental;

  /// Saves the form. Throw to keep the form open with the error shown.
  final Future<void> Function(IntakeSubmission form) onSubmit;

  final Patient? patient;
  final PatientIntake? intake;
  final String submitLabel;

  @override
  State<PatientIntakeForm> createState() => _PatientIntakeFormState();
}

enum _Step {
  about('About you', 'About the patient', Icons.person_outline),
  contact('Contact', 'Contact', Icons.phone_outlined),
  health('Health', 'Health', Icons.favorite_outline),
  consent('Review & consent', 'Review & consent', Icons.verified_outlined);

  const _Step(this.patientTitle, this.staffTitle, this.icon);

  final String patientTitle;
  final String staffTitle;
  final IconData icon;
}

class _PatientIntakeFormState extends State<PatientIntakeForm> {
  final _formKeys = {for (final s in _Step.values) s: GlobalKey<FormState>()};
  final _scroll = ScrollController();
  _Step _step = _Step.about;

  late final _name = TextEditingController(text: widget.patient?.name);
  late final _dob = TextEditingController(
      text: widget.patient?.dateOfBirth == null
          ? ''
          : DateFormat('MM/dd/yyyy').format(widget.patient!.dateOfBirth!));
  late final _occupation = TextEditingController(text: widget.patient?.occupation);
  late final _phone = TextEditingController(text: widget.patient?.phone);
  late final _email = TextEditingController(text: widget.patient?.email);
  late final _address = TextEditingController(text: widget.patient?.address);
  late final _ecName =
      TextEditingController(text: widget.patient?.emergencyContactName);
  late final _ecPhone =
      TextEditingController(text: widget.patient?.emergencyContactPhone);

  late final _reason = TextEditingController(text: widget.intake?.reasonForVisit);
  late final _lastDental =
      TextEditingController(text: widget.intake?.lastDentalVisit);
  late final _physician = TextEditingController(text: widget.intake?.physicianName);
  late final _treatment =
      TextEditingController(text: widget.intake?.treatmentDetails);
  late final _medications = TextEditingController(text: widget.intake?.medications);
  late final _allergiesOther =
      TextEditingController(text: widget.intake?.allergiesOther);
  late final _conditionsOther =
      TextEditingController(text: widget.intake?.conditionsOther);
  final _signedName = TextEditingController();

  late bool _byGuardian = widget.intake?.guardian != null;
  late GuardianRelationship? _gRelationship = widget.intake?.guardian?.relationship;
  late final _gName = TextEditingController(text: widget.intake?.guardian?.name);
  late final _gPhone = TextEditingController(text: widget.intake?.guardian?.phone);
  late final _gEmail = TextEditingController(text: widget.intake?.guardian?.email);

  late Sex? _sex = widget.patient?.sex;
  late bool? _underTreatment = widget.intake?.underTreatment;
  late bool? _takesMedications = widget.intake?.takesMedications;
  late final Set<IntakeAllergy> _allergies = {...?widget.intake?.allergies};
  late final Set<IntakeCondition> _conditions = {...?widget.intake?.conditions};
  late bool? _pregnant = widget.intake?.pregnant;
  late bool? _nursing = widget.intake?.nursing;
  late bool? _birthControl = widget.intake?.birthControl;
  bool _consent = false;

  bool _busy = false;
  String? _error;

  /// The patient is holding the device, answering about themself.
  bool get _you => _holding && !_byGuardian;

  /// The device is with the patient's side (the patient or their guardian),
  /// not the front desk. Decides the wording of the dialogs and the consent.
  bool get _holding => widget.audience == IntakeAudience.patient;

  /// "your" / "the patient's" and friends, by who the questions are about.
  String _t(String patient, String staff) => _you ? patient : staff;

  @override
  void dispose() {
    for (final c in [
      _name, _dob, _occupation, _phone, _email, _address, _ecName, _ecPhone,
      _reason, _lastDental, _physician, _treatment, _medications,
      _allergiesOther, _conditionsOther, _signedName, _gName, _gPhone, _gEmail,
    ]) {
      c.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  // ── Navigation ───────────────────────────────────────────────────────────

  void _go(_Step step) {
    setState(() {
      _step = step;
      _error = null;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _next() {
    if (!(_formKeys[_step]!.currentState?.validate() ?? false)) return;
    if (_step == _Step.consent) {
      _submit();
    } else {
      _go(_Step.values[_step.index + 1]);
    }
  }

  Future<void> _submit() async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_holding
            ? (_byGuardian ? 'Send this information?' : 'Send your information?')
            : 'Save this form?'),
        content: Text(_holding
            ? 'Please check that everything is correct. You can go back and '
                'change anything before sending.'
            : _byGuardian
                ? 'Check the answers with the parent or guardian before saving.'
                : 'Check the answers with the patient before saving.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Check again'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(widget.submitLabel),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSubmit(_submission());
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  IntakeSubmission _submission() {
    String? text(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();
    final dob = _parseDate(_dob.text);
    final female = _sex == Sex.female;
    return IntakeSubmission(
      person: {
        'full_name': _name.text.trim(),
        'date_of_birth': dob == null ? null : DateFormat('yyyy-MM-dd').format(dob),
        'sex': _sex?.wire,
        'occupation': text(_occupation),
        'phone': text(_phone),
        'email': text(_email),
        'address': text(_address),
        'emergency_contact_name': text(_ecName),
        'emergency_contact_phone': text(_ecPhone),
      },
      intake: {
        'reason_for_visit': text(_reason),
        'last_dental_visit': widget.isDental ? text(_lastDental) : null,
        'physician_name': text(_physician),
        'under_treatment': _underTreatment,
        'treatment_details': text(_treatment),
        'takes_medications': _takesMedications,
        'medications': text(_medications),
        'allergies': [for (final a in _allergies) a.wire],
        'allergies_other': text(_allergiesOther),
        'conditions': [for (final c in _conditions) c.wire],
        'conditions_other': text(_conditionsOther),
        'pregnant': female ? _pregnant : null,
        'nursing': female ? _nursing : null,
        'birth_control': female ? _birthControl : null,
        'filled_by_guardian': _byGuardian,
        if (_byGuardian) ...{
          'guardian_name': _gName.text.trim(),
          'guardian_relationship': _gRelationship?.wire,
          'guardian_phone': _gPhone.text.trim(),
          'guardian_email': text(_gEmail),
        },
        'signed_name': _signedName.text.trim(),
        'consent': _consent,
      },
    );
  }

  // ── Layout ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final last = _step == _Step.consent;

    final content = switch (_step) {
      _Step.about => _aboutStep(),
      _Step.contact => _contactStep(),
      _Step.health => _healthStep(),
      _Step.consent => _consentStep(),
    };

    return Column(
      children: [
        LinearProgressIndicator(
          value: (_step.index + 1) / _Step.values.length,
          minHeight: 4,
        ),
        Expanded(
          child: SingleChildScrollView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Form(
                  key: _formKeys[_step],
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Step ${_step.index + 1} of ${_Step.values.length}',
                        style: theme.textTheme.labelLarge
                            ?.copyWith(color: cs.primary),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(_step.icon, color: cs.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _step == _Step.about && _byGuardian
                                  ? (_holding
                                      ? 'About you and the patient'
                                      : 'Guardian and patient')
                                  : _you
                                      ? _step.patientTitle
                                      : _step.staffTitle,
                              style: theme.textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      ...content,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        Material(
          elevation: 3,
          color: cs.surfaceContainer,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(_error!,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: cs.error)),
                        ),
                      Row(
                        children: [
                          if (_step != _Step.about) ...[
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                    minimumSize: const Size(0, 56)),
                                onPressed: _busy
                                    ? null
                                    : () => _go(_Step.values[_step.index - 1]),
                                icon: const Icon(Icons.arrow_back),
                                label: const Text('Back'),
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],
                          Expanded(
                            flex: 2,
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                  minimumSize: const Size(0, 56),
                                  textStyle: const TextStyle(
                                      fontSize: 17, fontWeight: FontWeight.w600)),
                              onPressed: _busy ? null : _next,
                              icon: _busy
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))
                                  : Icon(last ? Icons.check : Icons.arrow_forward),
                              label: Text(last ? widget.submitLabel : 'Next'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Steps ────────────────────────────────────────────────────────────────

  List<Widget> _aboutStep() => [
        _guardianSwitch(),
        if (_byGuardian) ...[
          _SectionLabel(_holding
              ? 'About you (parent or guardian)'
              : 'Parent or guardian'),
          _field(_gName,
              label: _holding ? 'Your full name' : 'Their full name',
              required: true,
              capitalization: TextCapitalization.words,
              autofill: _holding ? AutofillHints.name : null),
          _Question(
            label: _holding
                ? 'You are the patient\'s'
                : 'They are the patient\'s',
            child: _ChoiceField<GuardianRelationship>(
              value: _gRelationship,
              options: {
                for (final r in GuardianRelationship.values) r: r.label
              },
              onChanged: (v) => setState(() => _gRelationship = v),
              requiredMessage: 'Please choose one',
            ),
          ),
          _field(_gPhone,
              label: _holding ? 'Your mobile number' : 'Their mobile number',
              required: true,
              keyboard: TextInputType.phone,
              autofill: _holding ? AutofillHints.telephoneNumber : null,
              validator: _validPhone),
          _field(_gEmail,
              label: _holding ? 'Your email' : 'Their email',
              keyboard: TextInputType.emailAddress,
              autofill: _holding ? AutofillHints.email : null,
              validator: _validEmail),
          const SizedBox(height: 8),
          const _SectionLabel('About the patient'),
        ],
        _field(_name,
            label: _byGuardian ? 'Patient\'s full name' : 'Full name',
            required: true,
            capitalization: TextCapitalization.words,
            autofill: _you ? AutofillHints.name : null),
        _DateOfBirthField(controller: _dob, label: _t('Your birthday', 'Birthday')),
        _Question(
          label: 'Sex',
          child: _ChoiceField<Sex>(
            value: _sex,
            options: {for (final s in Sex.values) s: s.label},
            onChanged: (v) => setState(() => _sex = v),
            requiredMessage: 'Please choose one',
          ),
        ),
        _field(_occupation,
            label: 'Occupation',
            capitalization: TextCapitalization.sentences),
      ];

  List<Widget> _contactStep() => [
        _field(_phone,
            label: 'Mobile number',
            helper: _byGuardian
                ? 'The patient\'s own. If they have none, use '
                    '${_holding ? 'yours' : 'the parent or guardian\'s'}.'
                : null,
            required: true,
            keyboard: TextInputType.phone,
            autofill: AutofillHints.telephoneNumber,
            validator: _validPhone),
        _field(_email,
            label: 'Email',
            keyboard: TextInputType.emailAddress,
            autofill: AutofillHints.email,
            validator: _validEmail),
        _field(_address,
            label: 'Home address',
            capitalization: TextCapitalization.words,
            maxLines: 2,
            autofill: AutofillHints.fullStreetAddress),
        const SizedBox(height: 8),
        _SectionLabel(_t('Who should we call in an emergency?',
            'Emergency contact')),
        _field(_ecName,
            label: 'Contact name', capitalization: TextCapitalization.words),
        _field(_ecPhone,
            label: 'Contact number',
            keyboard: TextInputType.phone,
            validator: (v) =>
                v == null || v.trim().isEmpty ? null : _validPhone(v)),
      ];

  List<Widget> _healthStep() {
    final cs = Theme.of(context).colorScheme;
    return [
      _field(_reason,
          label: _t('What brings you in today?', 'Reason for visit'),
          capitalization: TextCapitalization.sentences,
          maxLines: 2),
      if (widget.isDental)
        _field(_lastDental,
            label: 'Last dental visit',
            hint: 'e.g. about a year ago',
            capitalization: TextCapitalization.sentences),
      _field(_physician,
          label: _t('Your regular doctor (if any)', 'Physician (if any)'),
          capitalization: TextCapitalization.words),
      _Question(
        label: _t('Are you being treated by a doctor right now?',
            'Under a doctor\'s treatment now?'),
        child: _ChoiceField<bool>(
          value: _underTreatment,
          options: const {true: 'Yes', false: 'No'},
          onChanged: (v) => setState(() => _underTreatment = v),
          requiredMessage: 'Please answer',
        ),
      ),
      if (_underTreatment == true)
        _field(_treatment,
            label: 'For what?', capitalization: TextCapitalization.sentences),
      _Question(
        label: _t('Are you taking any medicines?', 'Taking any medicines?'),
        child: _ChoiceField<bool>(
          value: _takesMedications,
          options: const {true: 'Yes', false: 'No'},
          onChanged: (v) => setState(() => _takesMedications = v),
          requiredMessage: 'Please answer',
        ),
      ),
      if (_takesMedications == true)
        _field(_medications,
            label: 'Which ones?',
            hint: 'Name and dose, e.g. Losartan 50 mg',
            required: true,
            capitalization: TextCapitalization.sentences,
            maxLines: 2),
      const SizedBox(height: 8),
      _SectionLabel(_t('Are you allergic to any of these?', 'Allergies')),
      Text('Tap all that apply. Leave blank if none.',
          style: TextStyle(color: cs.onSurfaceVariant)),
      const SizedBox(height: 8),
      _Chips<IntakeAllergy>(
        options: {for (final a in IntakeAllergy.values) a: a.label},
        selected: _allergies,
        onChanged: () => setState(() {}),
        selectedColor: cs.errorContainer,
      ),
      _field(_allergiesOther,
          label: 'Other allergies',
          capitalization: TextCapitalization.sentences),
      const SizedBox(height: 8),
      _SectionLabel(_t('Do you have, or have you had, any of these?',
          'Medical conditions')),
      Text('Tap all that apply. Leave blank if none.',
          style: TextStyle(color: cs.onSurfaceVariant)),
      const SizedBox(height: 8),
      _Chips<IntakeCondition>(
        options: {for (final c in IntakeCondition.values) c: c.label},
        selected: _conditions,
        onChanged: () => setState(() {}),
      ),
      _field(_conditionsOther,
          label: 'Other conditions',
          capitalization: TextCapitalization.sentences),
      if (_sex == Sex.female) ...[
        const SizedBox(height: 8),
        _SectionLabel(_t('For women', 'Women')),
        _Question(
          label: _t('Are you pregnant?', 'Pregnant?'),
          child: _ChoiceField<bool>(
            value: _pregnant,
            options: const {true: 'Yes', false: 'No'},
            onChanged: (v) => setState(() => _pregnant = v),
          ),
        ),
        _Question(
          label: _t('Are you breastfeeding?', 'Breastfeeding?'),
          child: _ChoiceField<bool>(
            value: _nursing,
            options: const {true: 'Yes', false: 'No'},
            onChanged: (v) => setState(() => _nursing = v),
          ),
        ),
        _Question(
          label: _t('Are you taking birth control pills?', 'On birth control pills?'),
          child: _ChoiceField<bool>(
            value: _birthControl,
            options: const {true: 'Yes', false: 'No'},
            onChanged: (v) => setState(() => _birthControl = v),
          ),
        ),
      ],
    ];
  }

  List<Widget> _consentStep() {
    final cs = Theme.of(context).colorScheme;
    final dob = _parseDate(_dob.text);
    final allergies = [
      for (final a in IntakeAllergy.values)
        if (_allergies.contains(a)) a.label,
      if (_allergiesOther.text.trim().isNotEmpty) _allergiesOther.text.trim(),
    ];
    final conditions = [
      for (final c in IntakeCondition.values)
        if (_conditions.contains(c)) c.label,
      if (_conditionsOther.text.trim().isNotEmpty) _conditionsOther.text.trim(),
    ];

    return [
      Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_byGuardian)
                _ReviewRow(
                    'Filled in by',
                    [
                      _gName.text.trim(),
                      if (_gRelationship != null) '(${_gRelationship!.label})',
                      if (_gPhone.text.trim().isNotEmpty) '· ${_gPhone.text.trim()}',
                    ].join(' '),
                    onEdit: () => _go(_Step.about)),
              _ReviewRow('Name', _name.text.trim(), onEdit: () => _go(_Step.about)),
              _ReviewRow(
                  'Birthday',
                  dob == null ? '—' : DateFormat('MMMM d, y').format(dob),
                  onEdit: () => _go(_Step.about)),
              _ReviewRow('Mobile', _phone.text.trim(),
                  onEdit: () => _go(_Step.contact)),
              _ReviewRow(
                  'Emergency contact',
                  [_ecName.text.trim(), _ecPhone.text.trim()]
                      .where((s) => s.isNotEmpty)
                      .join(' · '),
                  onEdit: () => _go(_Step.contact)),
              _ReviewRow(
                  'Medicines',
                  _takesMedications == true
                      ? _medications.text.trim()
                      : 'None',
                  onEdit: () => _go(_Step.health)),
              _ReviewRow(
                  'Allergies', allergies.isEmpty ? 'None' : allergies.join(', '),
                  highlight: allergies.isNotEmpty,
                  onEdit: () => _go(_Step.health)),
              _ReviewRow('Conditions',
                  conditions.isEmpty ? 'None' : conditions.join(', '),
                  onEdit: () => _go(_Step.health)),
            ],
          ),
        ),
      ),
      const SizedBox(height: 24),
      FormField<bool>(
        initialValue: _consent,
        validator: (v) => v == true
            ? null
            : _holding
                ? 'Please tick the box to continue'
                : _byGuardian
                    ? 'The parent or guardian must agree before saving'
                    : 'The patient must agree before saving',
        builder: (field) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CheckboxListTile(
              value: _consent,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: (v) {
                setState(() => _consent = v ?? false);
                field.didChange(v);
              },
              title: Text(_consentText()),
            ),
            if (field.hasError)
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Text(field.errorText!,
                    style: TextStyle(color: cs.error, fontSize: 12)),
              ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      _field(_signedName,
          label: _holding
              ? 'Type your full name to sign'
              : _byGuardian
                  ? 'Parent or guardian\'s full name (signature)'
                  : 'Patient\'s full name (signature)',
          required: true,
          capitalization: TextCapitalization.words),
    ];
  }

  String _consentText() {
    const law = 'as allowed by the Data Privacy Act of 2012 (RA 10173).';
    final clinic = widget.clinicName;
    if (!_byGuardian) {
      return _holding
          ? 'I confirm that this information is true and complete, and I agree '
              'to $clinic collecting and using it to care for me, $law'
          : 'The patient confirms that this information is true and complete, '
              'and agrees to $clinic collecting and using it for their care, $law';
    }
    return _holding
        ? 'As the patient\'s parent or guardian, I confirm that this '
            'information is true and complete, and I agree on their behalf to '
            '$clinic collecting and using it for their care, $law'
        : 'The patient\'s parent or guardian confirms that this information is '
            'true and complete, and agrees on the patient\'s behalf to $clinic '
            'collecting and using it for their care, $law';
  }

  // ── Pieces ───────────────────────────────────────────────────────────────

  /// Optional: off unless a parent or guardian is answering.
  Widget _guardianSwitch() {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Card(
        margin: EdgeInsets.zero,
        color: _byGuardian ? cs.secondaryContainer : null,
        child: SwitchListTile(
          value: _byGuardian,
          onChanged: (v) => setState(() => _byGuardian = v),
          secondary: const Icon(Icons.family_restroom_outlined),
          title: Text(_holding
              ? 'I\'m a parent or guardian filling this in for the patient'
              : 'A parent or guardian is answering for the patient'),
          subtitle: const Text('For a child, or someone who cannot answer '
              'for themself'),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller, {
    required String label,
    String? hint,
    String? helper,
    bool required = false,
    TextInputType? keyboard,
    TextCapitalization capitalization = TextCapitalization.none,
    int maxLines = 1,
    String? autofill,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        keyboardType: maxLines > 1 ? TextInputType.multiline : keyboard,
        textCapitalization: capitalization,
        minLines: 1,
        maxLines: maxLines,
        autofillHints: autofill == null ? null : [autofill],
        style: const TextStyle(fontSize: 17),
        decoration: InputDecoration(
          labelText: required ? '$label *' : label,
          hintText: hint,
          helperText: helper,
          helperMaxLines: 2,
        ),
        validator: (v) {
          if (required && (v == null || v.trim().isEmpty)) return 'Required';
          return validator?.call(v);
        },
      ),
    );
  }

  static String? _validEmail(String? v) =>
      v == null || v.trim().isEmpty || v.contains('@')
          ? null
          : 'Check the email address';

  static String? _validPhone(String? v) {
    final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
    return digits.length < 7 ? 'Check the number' : null;
  }
}

/// MM/DD/YYYY, as Filipino forms write it. Typed rather than picked: a
/// calendar is a long way to scroll to 1958. The calendar is there too.
class _DateOfBirthField extends StatelessWidget {
  const _DateOfBirthField({required this.controller, required this.label});

  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [_DateMaskFormatter()],
        style: const TextStyle(fontSize: 17),
        decoration: InputDecoration(
          labelText: '$label *',
          hintText: 'MM/DD/YYYY',
          suffixIcon: IconButton(
            tooltip: 'Pick from a calendar',
            icon: const Icon(Icons.calendar_month_outlined),
            onPressed: () async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: _parseDate(controller.text) ?? DateTime(now.year - 30),
                firstDate: DateTime(now.year - 120),
                lastDate: now,
                initialDatePickerMode: DatePickerMode.year,
              );
              if (picked != null) {
                controller.text = DateFormat('MM/dd/yyyy').format(picked);
              }
            },
          ),
        ),
        validator: (v) {
          if (v == null || v.trim().isEmpty) return 'Required';
          final d = _parseDate(v);
          final now = DateTime.now();
          if (d == null) return 'Use MM/DD/YYYY, e.g. 04/02/1990';
          if (d.isAfter(now) || d.year < now.year - 120) {
            return 'Check the year';
          }
          return null;
        },
      ),
    );
  }
}

/// A real calendar date from MM/DD/YYYY, or null. `DateTime` rolls 02/31 over
/// into March, so the parts are checked against what comes back.
DateTime? _parseDate(String text) {
  final m = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(text.trim());
  if (m == null) return null;
  final month = int.parse(m[1]!), day = int.parse(m[2]!), year = int.parse(m[3]!);
  final d = DateTime(year, month, day);
  return d.year == year && d.month == month && d.day == day ? d : null;
}

/// Digits only, with the slashes put in as they are typed.
class _DateMaskFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 8) digits = digits.substring(0, 8);
    final b = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i == 2 || i == 4) b.write('/');
      b.write(digits[i]);
    }
    final text = b.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w600)),
    );
  }
}

class _Question extends StatelessWidget {
  const _Question({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

/// One answer from a few, as big side-by-side buttons. Required when
/// [requiredMessage] is given.
class _ChoiceField<T> extends StatelessWidget {
  const _ChoiceField({
    required this.value,
    required this.options,
    required this.onChanged,
    this.requiredMessage,
  });

  final T? value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;
  final String? requiredMessage;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FormField<T>(
      initialValue: value,
      validator: (_) =>
          requiredMessage != null && value == null ? requiredMessage : null,
      builder: (field) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (final e in options.entries) ...[
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: value == e.key
                        ? FilledButton.icon(
                            onPressed: () {},
                            icon: const Icon(Icons.check),
                            label: Text(e.value),
                          )
                        : OutlinedButton(
                            onPressed: () {
                              onChanged(e.key);
                              field.didChange(e.key);
                            },
                            child: Text(e.value),
                          ),
                  ),
                ),
                if (e.key != options.keys.last) const SizedBox(width: 12),
              ],
            ],
          ),
          if (field.hasError)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 12),
              child: Text(field.errorText!,
                  style: TextStyle(color: cs.error, fontSize: 12)),
            ),
        ],
      ),
    );
  }
}

class _Chips<T> extends StatelessWidget {
  const _Chips({
    required this.options,
    required this.selected,
    required this.onChanged,
    this.selectedColor,
  });

  final Map<T, String> options;

  /// Changed in place.
  final Set<T> selected;
  final VoidCallback onChanged;
  final Color? selectedColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final e in options.entries)
            FilterChip(
              label: Text(e.value, style: const TextStyle(fontSize: 15)),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
              selected: selected.contains(e.key),
              selectedColor: selectedColor,
              onSelected: (on) {
                on ? selected.add(e.key) : selected.remove(e.key);
                onChanged();
              },
            ),
        ],
      ),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow(this.label, this.value,
      {required this.onEdit, this.highlight = false});

  final String label;
  final String value;
  final VoidCallback onEdit;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onEdit,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 140,
              child: Text(label, style: TextStyle(color: cs.onSurfaceVariant)),
            ),
            Expanded(
              child: Text(value.isEmpty ? '—' : value,
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: highlight ? cs.error : null)),
            ),
            Icon(Icons.edit_outlined, size: 18, color: cs.outline),
          ],
        ),
      ),
    );
  }
}
