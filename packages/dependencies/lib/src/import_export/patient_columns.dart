import '../models/patient_intake.dart';
import 'import_common.dart';

/// The columns of a patients file, in and out: the patient information form,
/// the clinic's chart note and a balance, as `import_patients` and
/// `export_patients` take and give them (20261003120000).
///
/// An exported file has these headers, in this order, and imports back as is.
/// A clinic's own spreadsheet rarely does, so every column also answers to
/// the names clinics tend to use ("Mobile no.", "Birthdate", "Surname").
enum PatientColumn implements ImportColumn {
  patientId('patient_id', 'Patient ID', _Cell.text, ['id', 'patient uuid']),
  chartNumber('chart_number', 'Chart no.', _Cell.text, [
    'chart number', 'chart', 'record no', 'record number', 'patient no',
    'patient number', 'file no', 'file number', 'folder no', 'case no',
  ]),
  fullName('full_name', 'Name', _Cell.text,
      ['full name', 'patient name', 'patient', 'complete name', 'pangalan']),
  lastName('last_name', 'Last name', _Cell.text,
      ['surname', 'family name', 'apelyido'], importOnly: true),
  firstName('first_name', 'First name', _Cell.text,
      ['given name', 'given names'], importOnly: true),
  middleName('middle_name', 'Middle name', _Cell.text,
      ['middle initial', 'mi', 'm i'], importOnly: true),
  phone('phone', 'Phone', _Cell.text, [
    'mobile', 'mobile no', 'mobile number', 'cellphone', 'cellphone no',
    'cell no', 'contact', 'contact no', 'contact number', 'phone number',
    'telephone', 'tel no',
  ]),
  email('email', 'Email', _Cell.text, ['email address', 'e mail']),
  dateOfBirth('date_of_birth', 'Birthday', _Cell.date,
      ['birthdate', 'birth date', 'date of birth', 'dob', 'bday', 'birthday']),
  sex('sex', 'Sex', _Cell.sex, ['gender', 'kasarian']),
  address('address', 'Address', _Cell.text,
      ['home address', 'residence', 'tirahan']),
  occupation('occupation', 'Occupation', _Cell.text, ['work', 'job', 'trabaho']),
  emergencyName('emergency_contact_name', 'Emergency contact', _Cell.text,
      ['emergency contact name', 'in case of emergency', 'person to contact']),
  emergencyPhone('emergency_contact_phone', 'Emergency contact phone',
      _Cell.text, ['emergency phone', 'emergency number', 'emergency contact no']),

  reasonForVisit('reason_for_visit', 'Reason for visit', _Cell.text,
      ['reason', 'chief complaint', 'complaint', 'reason for consultation']),
  lastDentalVisit('last_dental_visit', 'Last dental visit', _Cell.text,
      ['previous dental visit', 'last visit to dentist']),
  physicianName('physician_name', 'Physician', _Cell.text,
      ['physician name', 'doctor', 'attending physician', 'family doctor']),
  underTreatment('under_treatment', 'Under treatment', _Cell.yesNo,
      ['under medical treatment', 'in good health under treatment']),
  treatmentDetails('treatment_details', 'Treatment details', _Cell.text,
      ['condition being treated', 'treatment']),
  takesMedications('takes_medications', 'Takes medications', _Cell.yesNo,
      ['taking medications', 'on medication', 'taking medication']),
  medications('medications', 'Medications', _Cell.text,
      ['medication', 'maintenance', 'maintenance medicines', 'medicines']),
  allergies('allergies', 'Allergies', _Cell.allergies, ['allergy', 'allergic to']),
  allergiesOther('allergies_other', 'Other allergies', _Cell.text,
      ['allergies other']),
  conditions('conditions', 'Conditions', _Cell.conditions,
      ['medical conditions', 'medical history', 'illnesses', 'diseases']),
  conditionsOther('conditions_other', 'Other conditions', _Cell.text,
      ['conditions other']),
  pregnant('pregnant', 'Pregnant', _Cell.yesNo, []),
  nursing('nursing', 'Nursing', _Cell.yesNo, ['breastfeeding']),
  birthControl('birth_control', 'Birth control', _Cell.yesNo,
      ['birth control pills', 'contraceptives']),
  guardianName('guardian_name', 'Guardian', _Cell.text,
      ['guardian name', 'parent', 'parent name', 'parent guardian']),
  guardianRelationship('guardian_relationship', 'Guardian relationship',
      _Cell.relationship, ['relationship', 'relation']),
  guardianPhone('guardian_phone', 'Guardian phone', _Cell.text,
      ['parent phone', 'guardian contact', 'guardian contact no']),
  guardianEmail('guardian_email', 'Guardian email', _Cell.text, ['parent email']),
  signedName('signed_name', 'Signed by', _Cell.text,
      ['signature', 'signed', 'signed name', 'signatory']),
  signedOn('signed_on', 'Signed on', _Cell.date,
      ['date signed', 'form date', 'consent date', 'date']),

  chartNote('chart_note', 'Clinic notes', _Cell.text, [
    'notes', 'note', 'clinical notes', 'chart notes', 'remarks', 'medical notes',
  ]),
  openingBalance('opening_balance', 'Opening balance', _Cell.money,
      ['balance forwarded', 'previous balance', 'old balance', 'unpaid balance']),

  balance('balance', 'Balance', _Cell.money, [], exportOnly: true),
  completedVisits('completed_visits', 'Completed visits', _Cell.text, [],
      exportOnly: true),
  lastVisit('last_visit', 'Last visit', _Cell.date, [], exportOnly: true),
  registeredOn('registered_on', 'Registered on', _Cell.date, [], exportOnly: true);

  const PatientColumn(this.key, this.header, this._cell, this.aliases,
      {this.importOnly = false, this.exportOnly = false});

  @override
  final String key;
  @override
  final String header;
  final _Cell _cell;
  @override
  final List<String> aliases;

  /// Parts of a name some files split up; joined into [fullName].
  final bool importOnly;

  /// Read-only facts an export adds (what is owed, visits): they come from
  /// the clinic's records, so an import ignores them.
  @override
  final bool exportOnly;

  static const _person = {
    fullName, phone, email, dateOfBirth, sex, address, occupation,
    emergencyName, emergencyPhone,
  };
  static const _intake = {
    reasonForVisit, lastDentalVisit, physicianName, underTreatment,
    treatmentDetails, takesMedications, medications, allergies, allergiesOther,
    conditions, conditionsOther, pregnant, nursing, birthControl, guardianName,
    guardianRelationship, guardianPhone, guardianEmail, signedName, signedOn,
  };

  bool get isIntake => _intake.contains(this);

  /// What the column picker offers for a file's column.
  static List<PatientColumn> get importable =>
      [for (final c in values) if (!c.exportOnly) c];

  /// An exported file's columns, in order. The front desk's has no notes
  /// column: they cannot read clinical notes, so it would only ever be blank,
  /// and blank looks like "none on file".
  static List<PatientColumn> exported({required bool withNotes}) => [
        for (final c in values)
          if (!c.importOnly && (withNotes || c != chartNote)) c,
      ];

  /// The template: every column an import takes, as one would type them.
  static List<PatientColumn> get template => [
        for (final c in values)
          if (!c.importOnly && !c.exportOnly && c != patientId) c,
      ];

  @override
  String get hint => switch (_cell) {
        _Cell.date => 'a date',
        _Cell.yesNo => 'Yes or No',
        _Cell.sex => 'Female or Male',
        _Cell.allergies || _Cell.conditions => 'a list, separated by ;',
        _Cell.money => 'an amount in pesos',
        _Cell.relationship => 'Parent or Guardian',
        _Cell.text => switch (this) {
            patientId => 'from an export; leave empty for new patients',
            signedName => 'the name the form was signed with',
            chartNote => 'doctors and admins only',
            _ => 'text',
          },
      };
}

enum _Cell { text, date, yesNo, sex, allergies, conditions, money, relationship }

/// Each of [headers]' columns with the [PatientColumn] it most likely holds,
/// or none.
List<PatientColumn?> matchHeaders(List<String> headers) =>
    matchColumns(headers, PatientColumn.importable);

/// Reads one row of a file whose columns are [columns] (from
/// [matchHeaders], or as the person picked them).
ImportRow readPatientRow(
  List<String> cells,
  List<PatientColumn?> columns, {
  required int row,
  DateOrder dateOrder = DateOrder.monthFirst,
}) {
  final errors = <String>[];
  final warnings = <String>[];
  final values = <PatientColumn, String>{};
  for (var i = 0; i < columns.length && i < cells.length; i++) {
    final c = columns[i];
    if (c == null || c.exportOnly) continue;
    final v = cleanCell(cells[i]);
    if (v.isNotEmpty) values[c] = v;
  }

  Object? read(PatientColumn c) {
    final raw = values[c];
    if (raw == null) return null;
    switch (c._cell) {
      case _Cell.text:
        return raw;
      case _Cell.date:
        final d = parseDate(raw, dateOrder);
        if (d == null) {
          errors.add('${c.header} "$raw" is not a date.');
        } else if (c == PatientColumn.dateOfBirth && d.isAfter(DateTime.now())) {
          errors.add('Birthday $raw is in the future.');
        }
        return d == null ? null : isoDate(d);
      case _Cell.yesNo:
        final b = parseYesNo(raw);
        if (b == null) errors.add('${c.header} "$raw" is not Yes or No.');
        return b;
      case _Cell.sex:
        final s = parseSex(raw);
        if (s == null) errors.add('Sex "$raw" is not Female or Male.');
        return s?.wire;
      case _Cell.money:
        final m = parsePesos(raw);
        if (m == null) {
          errors.add('${c.header} "$raw" is not an amount.');
        } else if (m < 0) {
          errors.add('${c.header} cannot be negative.');
        }
        return m;
      case _Cell.relationship:
        return parseRelationship(raw).wire;
      case _Cell.allergies:
      case _Cell.conditions:
        return raw; // split below, with the "other" columns
    }
  }

  final person = <String, dynamic>{};
  final intake = <String, dynamic>{};
  for (final c in PatientColumn.values) {
    final v = read(c);
    if (v == null) continue;
    if (PatientColumn._person.contains(c)) person[c.key] = v;
    if (c.isIntake) intake[c.key] = v;
  }

  // The name: whole, "SURNAME, Given", or in parts.
  var name = person['full_name'] as String? ?? [
        values[PatientColumn.firstName],
        values[PatientColumn.middleName],
        values[PatientColumn.lastName],
      ].whereType<String>().join(' ');
  name = tidyName(name);
  if (name.isEmpty) {
    errors.add('No name.');
  } else {
    person['full_name'] = name;
  }

  // Lists: what the form lists by name, the rest as "other".
  if (values[PatientColumn.allergies] case final raw?) {
    final (known, other) = _splitList(raw, _allergyWords);
    intake['allergies'] = [for (final a in known) a.wire];
    final rest = [other, values[PatientColumn.allergiesOther]].whereType<String>().join('; ');
    if (rest.isNotEmpty) intake['allergies_other'] = rest;
  }
  if (values[PatientColumn.conditions] case final raw?) {
    final (known, other) = _splitList(raw, _conditionWords);
    intake['conditions'] = [for (final c in known) c.wire];
    final rest = [other, values[PatientColumn.conditionsOther]].whereType<String>().join('; ');
    if (rest.isNotEmpty) intake['conditions_other'] = rest;
  }

  // A medicine named answers "takes medications"; a treatment named answers
  // "under treatment". The reverse is never guessed.
  if (intake['medications'] != null) intake['takes_medications'] ??= true;
  if (intake['treatment_details'] != null) intake['under_treatment'] ??= true;

  if (intake['guardian_name'] != null &&
      (intake['guardian_relationship'] == null || intake['guardian_phone'] == null)) {
    errors.add('A guardian needs a relationship (Parent or Guardian) and a phone.');
  }

  final json = <String, dynamic>{
    'row': row,
    if (values[PatientColumn.patientId] case final id?) 'patient_id': id,
    if (values[PatientColumn.chartNumber] case final n?) 'chart_number': n,
    'person': person,
    if (intake.isNotEmpty) 'intake': intake,
    if (values[PatientColumn.chartNote] case final n?) 'chart_note': n,
    if (read(PatientColumn.openingBalance) case final double b when b > 0)
      'opening_balance': b.toStringAsFixed(2),
  };

  if (values[PatientColumn.patientId] case final id?
      when !RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(id)) {
    errors.add('Patient ID "$id" is not one this app made. Clear it for a new patient.');
  }
  if ((person['phone'] as String?) == null && name.isNotEmpty) {
    warnings.add('No phone number.');
  }

  return ImportRow(
    row: row,
    json: json,
    name: name,
    errors: errors.toSet().toList(),
    warnings: warnings,
    cells: cells,
  );
}

/// One export_patients row as the cells of [columns].
List<String> exportPatientCells(Map<String, dynamic> p, List<PatientColumn> columns) {
  final intake = p['intake'] as Map<String, dynamic>? ?? const {};
  return [
    for (final c in columns)
      () {
        final v = c.isIntake ? intake[c.key] : p[c.key];
        if (v == null) return '';
        return switch (c._cell) {
          _Cell.yesNo => v == true ? 'Yes' : 'No',
          _Cell.sex => Sex.fromWire(v as String)?.label ?? '',
          _Cell.relationship => GuardianRelationship.fromWire(v as String).label,
          _Cell.allergies => [
              for (final w in v as List) IntakeAllergy.fromWire(w as String)?.label ?? w,
            ].join('; '),
          _Cell.conditions => [
              for (final w in v as List) IntakeCondition.fromWire(w as String)?.label ?? w,
            ].join('; '),
          _Cell.money => (v as num).toDouble().toStringAsFixed(2),
          _ => v.toString(),
        };
      }(),
  ];
}

// ── Reading cells ──────────────────────────────────────────────────────────

Sex? parseSex(String raw) => switch (raw.trim().toLowerCase()) {
      'f' || 'female' || 'babae' || 'woman' => Sex.female,
      'm' || 'male' || 'lalaki' || 'man' => Sex.male,
      _ => null,
    };

GuardianRelationship parseRelationship(String raw) =>
    switch (raw.trim().toLowerCase()) {
      'parent' || 'mother' || 'father' || 'mom' || 'dad' || 'nanay' ||
      'tatay' || 'ina' || 'ama' || 'mama' || 'papa' =>
        GuardianRelationship.parent,
      _ => GuardianRelationship.guardian,
    };

(List<T>, String?) _splitList<T>(String raw, Map<String, T> words) {
  final known = <T>[];
  final other = <String>[];
  for (final part in raw.split(RegExp(r'[;,/\n]'))) {
    final p = part.trim();
    if (p.isEmpty || blankWords.contains(p.toLowerCase())) continue;
    final n = normHeader(p);
    T? hit;
    for (final e in words.entries) {
      // Whole words: "tb" is tuberculosis, but not inside another word.
      if (' $n '.contains(' ${e.key} ')) {
        hit = e.value;
        break;
      }
    }
    if (hit == null) {
      other.add(p);
    } else if (!known.contains(hit)) {
      known.add(hit);
    }
  }
  return (known, other.isEmpty ? null : other.join('; '));
}

/// Words that name each item on the form's lists, as typed in files.
final Map<String, IntakeAllergy> _allergyWords = {
  for (final a in IntakeAllergy.values) normHeader(a.label): a,
  for (final a in IntakeAllergy.values) normHeader(a.wire): a,
  'anesthesia': IntakeAllergy.localAnesthetic,
  'anesthetic': IntakeAllergy.localAnesthetic,
  'anaesthetic': IntakeAllergy.localAnesthetic,
  'lidocaine': IntakeAllergy.localAnesthetic,
  'penicilin': IntakeAllergy.penicillin,
  'amoxicillin': IntakeAllergy.penicillin,
  'antibiotic': IntakeAllergy.otherAntibiotics,
  'sulfa': IntakeAllergy.sulfa,
  'aspirin': IntakeAllergy.aspirin,
  'latex': IntakeAllergy.latex,
};

final Map<String, IntakeCondition> _conditionWords = {
  for (final c in IntakeCondition.values) normHeader(c.label): c,
  for (final c in IntakeCondition.values) normHeader(c.wire): c,
  'hypertension': IntakeCondition.highBloodPressure,
  'hypertensive': IntakeCondition.highBloodPressure,
  'high bp': IntakeCondition.highBloodPressure,
  'hbp': IntakeCondition.highBloodPressure,
  'hypotension': IntakeCondition.lowBloodPressure,
  'low bp': IntakeCondition.lowBloodPressure,
  'heart': IntakeCondition.heartDisease,
  'cardiac': IntakeCondition.heartDisease,
  'diabetes': IntakeCondition.diabetes,
  'diabetic': IntakeCondition.diabetes,
  'asthma': IntakeCondition.asthma,
  'bleeding': IntakeCondition.bleedingDisorder,
  'hemophilia': IntakeCondition.bleedingDisorder,
  'anemia': IntakeCondition.anemia,
  'anemic': IntakeCondition.anemia,
  'hepatitis': IntakeCondition.hepatitis,
  'liver': IntakeCondition.hepatitis,
  'kidney': IntakeCondition.kidneyDisease,
  'thyroid': IntakeCondition.thyroidProblem,
  'goiter': IntakeCondition.thyroidProblem,
  'epilepsy': IntakeCondition.epilepsy,
  'seizure': IntakeCondition.epilepsy,
  'stroke': IntakeCondition.stroke,
  'cancer': IntakeCondition.cancer,
  'tuberculosis': IntakeCondition.tuberculosis,
  'tb': IntakeCondition.tuberculosis,
  'ptb': IntakeCondition.tuberculosis,
};
