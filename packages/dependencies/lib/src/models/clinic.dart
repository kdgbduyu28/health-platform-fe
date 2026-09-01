import 'clinic_type.dart';

/// A clinic row. The apps address clinics by [ClinicType] (the build flavor),
/// but every write needs the database's `clinic_id`, so this carries both.
class Clinic {
  const Clinic({
    required this.id,
    required this.type,
    required this.name,
  });

  final String id;
  final ClinicType type;
  final String name;

  factory Clinic.fromJson(Map<String, dynamic> json) => Clinic(
        id: json['id'] as String,
        type: ClinicType.fromWire(json['type'] as String),
        name: json['name'] as String,
      );
}
