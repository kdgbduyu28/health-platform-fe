import 'package:flutter/material.dart';

enum ClinicType {
  dental,
  optometry,
  pedia;

  String get displayName => switch (this) {
        ClinicType.dental => 'Dental',
        ClinicType.optometry => 'Eye Care',
        ClinicType.pedia => 'Pediatrics',
      };

  String get clinicName => switch (this) {
        ClinicType.dental => 'Smile Dental Clinic',
        ClinicType.optometry => 'ClearVision Eye Clinic',
        ClinicType.pedia => 'Little Stars Pediatrics',
      };

  Color get seedColor => switch (this) {
        ClinicType.dental => const Color(0xFF00897B),
        ClinicType.optometry => const Color(0xFF1565C0),
        ClinicType.pedia => const Color(0xFFE65100),
      };

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
