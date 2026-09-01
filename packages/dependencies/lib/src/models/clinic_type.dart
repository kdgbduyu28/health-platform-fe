import 'package:flutter/material.dart';

import '../theme/brand.dart';

enum ClinicType {
  dental,
  optometry,
  pedia;

  /// The enum labels in Postgres (`public.clinic_type`) are identical to these
  /// Dart names, so the wire format needs no translation table — but going
  /// through here keeps the coupling explicit and fails loudly if that ever
  /// stops being true.
  static ClinicType fromWire(String value) => ClinicType.values.byName(value);

  String get wire => name;

  String get displayName => switch (this) {
    ClinicType.dental => 'Dental',
    ClinicType.optometry => 'Eye Care',
    ClinicType.pedia => 'Pediatrics',
  };

  String get clinicName => switch (this) {
    ClinicType.dental => 'D-Touch Dental Clinic',
    ClinicType.optometry => 'ClearVision Eye Clinic',
    ClinicType.pedia => 'Little Stars Pediatrics',
  };

  /// All three flavors share the D-Touch brown. The palette used to be a
  /// different hue per clinic (teal / blue / orange), which predates having a
  /// real brand to follow.
  Color get seedColor => Brand.brown;

  /// Whether this flavor may show the D-Touch lockup.
  ///
  /// The wordmark reads "DENTAL CLINIC", so putting it on the other two would
  /// brand an eye clinic and a paediatric clinic as a dental practice. They
  /// share the brown palette but keep their own name in text.
  ///
  /// If D-Touch takes over all three, this becomes `=> true` and the clinic
  /// names in the database change to match.
  bool get isDTouchBranded => this == ClinicType.dental;

  IconData get icon => switch (this) {
    ClinicType.dental => Icons.medical_services_outlined,
    ClinicType.optometry => Icons.remove_red_eye_outlined,
    ClinicType.pedia => Icons.child_care_outlined,
  };

  List<String> get services => switch (this) {
    ClinicType.dental => [
      'Teeth Cleaning',
      'Tooth Extraction',
      'Dental Filling',
      'Root Canal',
      'Braces Adjustment',
      'Teeth Whitening',
      'Dental X-Ray',
      'Wisdom Tooth Removal',
    ],
    ClinicType.optometry => [
      'Eye Examination',
      'Contact Lens Fitting',
      'Eyeglasses Prescription',
      'Glaucoma Screening',
      'LASIK Consultation',
      'Retinal Exam',
      'Low Vision Assessment',
    ],
    ClinicType.pedia => [
      'Well-Child Visit',
      'Vaccination',
      'Sick Visit',
      'Growth Assessment',
      'Development Screening',
      'Newborn Check-up',
      'School Physical',
    ],
  };
}
