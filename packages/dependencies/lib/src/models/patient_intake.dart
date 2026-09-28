/// The patient information form: medical history and consent, one per chart.
/// Mirrors `public.patient_intakes` (20260927120000, guardian 20261001120000).
///
/// Who someone is — name, birthday, contact, emergency contact — is on the
/// person and shared by every clinic; see [Patient]. What they told THIS
/// clinic about their health is here, and no other clinic can read it.
class PatientIntake {
  const PatientIntake({
    required this.patientId,
    required this.underTreatment,
    required this.takesMedications,
    required this.consentAt,
    required this.signedName,
    required this.source,
    required this.updatedAt,
    this.reasonForVisit,
    this.lastDentalVisit,
    this.physicianName,
    this.treatmentDetails,
    this.medications,
    this.allergies = const {},
    this.allergiesOther,
    this.conditions = const {},
    this.conditionsOther,
    this.pregnant,
    this.nursing,
    this.birthControl,
    this.guardian,
  });

  final String patientId;
  final String? reasonForVisit;
  final String? lastDentalVisit;
  final String? physicianName;
  final bool underTreatment;
  final String? treatmentDetails;
  final bool takesMedications;
  final String? medications;
  final Set<IntakeAllergy> allergies;
  final String? allergiesOther;
  final Set<IntakeCondition> conditions;
  final String? conditionsOther;

  /// Null when not asked (only women are).
  final bool? pregnant;
  final bool? nursing;
  final bool? birthControl;

  /// Who answered for the patient, when it was not the patient themself.
  final IntakeGuardian? guardian;

  final DateTime consentAt;
  final String signedName;
  final IntakeSource source;
  final DateTime updatedAt;

  bool get hasAllergies => allergies.isNotEmpty || allergiesOther != null;

  /// Every allergy as the patient would read it, the checklist first.
  List<String> get allergyLabels => [
        for (final a in IntakeAllergy.values)
          if (allergies.contains(a)) a.label,
        if (allergiesOther != null) allergiesOther!,
      ];

  List<String> get conditionLabels => [
        for (final c in IntakeCondition.values)
          if (conditions.contains(c)) c.label,
        if (conditionsOther != null) conditionsOther!,
      ];

  factory PatientIntake.fromJson(Map<String, dynamic> json) => PatientIntake(
        patientId: json['patient_id'] as String,
        reasonForVisit: json['reason_for_visit'] as String?,
        lastDentalVisit: json['last_dental_visit'] as String?,
        physicianName: json['physician_name'] as String?,
        underTreatment: json['under_treatment'] as bool,
        treatmentDetails: json['treatment_details'] as String?,
        takesMedications: json['takes_medications'] as bool,
        medications: json['medications'] as String?,
        allergies: _wireSet(json['allergies'], IntakeAllergy.fromWire),
        allergiesOther: json['allergies_other'] as String?,
        conditions: _wireSet(json['conditions'], IntakeCondition.fromWire),
        conditionsOther: json['conditions_other'] as String?,
        pregnant: json['pregnant'] as bool?,
        nursing: json['nursing'] as bool?,
        birthControl: json['birth_control'] as bool?,
        guardian: IntakeGuardian.fromJson(json),
        consentAt: DateTime.parse(json['consent_at'] as String).toLocal(),
        signedName: json['signed_name'] as String,
        source: IntakeSource.fromWire(json['source'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String).toLocal(),
      );
}

/// Values this build does not know (a newer checklist) are skipped rather
/// than failing the whole form.
Set<T> _wireSet<T extends Object>(Object? value, T? Function(String) parse) => {
      for (final w in value as List<dynamic>? ?? const [])
        if (parse(w as String) case final v?) v,
    };

/// A parent or guardian who filled in the form for the patient: a child, or
/// an adult who cannot answer for themself. Recorded per form, not on the
/// person, so a grown-up patient's own next form drops it.
class IntakeGuardian {
  const IntakeGuardian({
    required this.name,
    required this.relationship,
    required this.phone,
    this.email,
  });

  final String name;
  final GuardianRelationship relationship;
  final String phone;
  final String? email;

  /// From the intake row's guardian_* columns; null when there is none.
  static IntakeGuardian? fromJson(Map<String, dynamic> json) {
    final name = json['guardian_name'] as String?;
    if (name == null) return null;
    return IntakeGuardian(
      name: name,
      relationship:
          GuardianRelationship.fromWire(json['guardian_relationship'] as String?),
      phone: json['guardian_phone'] as String? ?? '',
      email: json['guardian_email'] as String?,
    );
  }
}

/// Mirrors `patient_intakes.guardian_relationship`.
enum GuardianRelationship {
  parent('parent', 'Parent'),
  guardian('guardian', 'Guardian');

  const GuardianRelationship(this.wire, this.label);

  final String wire;
  final String label;

  static GuardianRelationship fromWire(String? wire) =>
      values.firstWhere((r) => r.wire == wire, orElse: () => guardian);
}

/// Who typed the form in.
enum IntakeSource {
  /// The patient, in the patient app.
  patientApp('patient_app', 'by the patient, in the app'),

  /// The patient, on the front desk's tablet.
  frontDeskTablet('front_desk_tablet', 'by the patient, on the front desk tablet'),

  /// The front desk, for the patient.
  staff('staff', 'by the front desk'),

  /// Brought in from a file (a paper form typed up, or another system).
  imported('import', 'from an imported file');

  const IntakeSource(this.wire, this.description);

  final String wire;

  /// Completes "Filled in …".
  final String description;

  static IntakeSource fromWire(String wire) =>
      values.firstWhere((s) => s.wire == wire, orElse: () => staff);
}

/// Mirrors `private.intake_allergies()`.
enum IntakeAllergy {
  localAnesthetic('local_anesthetic', 'Local anesthetic (e.g. lidocaine)'),
  penicillin('penicillin', 'Penicillin'),
  otherAntibiotics('other_antibiotics', 'Other antibiotics'),
  sulfa('sulfa', 'Sulfa drugs'),
  aspirin('aspirin', 'Aspirin'),
  latex('latex', 'Latex');

  const IntakeAllergy(this.wire, this.label);

  final String wire;
  final String label;

  static IntakeAllergy? fromWire(String wire) {
    for (final a in values) {
      if (a.wire == wire) return a;
    }
    return null;
  }
}

/// Mirrors `private.intake_conditions()`.
enum IntakeCondition {
  highBloodPressure('high_blood_pressure', 'High blood pressure'),
  lowBloodPressure('low_blood_pressure', 'Low blood pressure'),
  heartDisease('heart_disease', 'Heart disease'),
  diabetes('diabetes', 'Diabetes'),
  asthma('asthma', 'Asthma'),
  bleedingDisorder('bleeding_disorder', 'Bleeding problems'),
  anemia('anemia', 'Anemia'),
  hepatitis('hepatitis', 'Hepatitis / liver disease'),
  kidneyDisease('kidney_disease', 'Kidney disease'),
  thyroidProblem('thyroid_problem', 'Thyroid problem'),
  epilepsy('epilepsy', 'Epilepsy / seizures'),
  stroke('stroke', 'Stroke'),
  cancer('cancer', 'Cancer'),
  tuberculosis('tuberculosis', 'Tuberculosis');

  const IntakeCondition(this.wire, this.label);

  final String wire;
  final String label;

  static IntakeCondition? fromWire(String wire) {
    for (final c in values) {
      if (c.wire == wire) return c;
    }
    return null;
  }
}

/// Mirrors `persons.sex`.
enum Sex {
  female('female', 'Female'),
  male('male', 'Male');

  const Sex(this.wire, this.label);

  final String wire;
  final String label;

  static Sex? fromWire(String? wire) {
    for (final s in values) {
      if (s.wire == wire) return s;
    }
    return null;
  }
}

/// A filled-in form, ready for `register_patient` / `save_patient_intake`:
/// the person's details and the intake, as the JSON the functions take.
class IntakeSubmission {
  const IntakeSubmission({required this.person, required this.intake});

  final Map<String, dynamic> person;
  final Map<String, dynamic> intake;
}
