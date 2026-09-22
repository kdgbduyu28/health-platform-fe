import 'clinic.dart';
import 'doctor.dart';
import 'service.dart';

/// What anyone — signed in or not — may see about a clinic: the page at
/// `/:clinic`, and the branding on its sign-in screen.
///
/// Read from `public.clinic_by_slug`, which leaves out the join code, the
/// doctors' accounts, and anything inactive. [clinic] therefore never carries
/// a join code, even for the clinic's own admin.
class ClinicPage {
  const ClinicPage({
    required this.clinic,
    this.services = const [],
    this.doctors = const [],
  });

  final Clinic clinic;
  final List<Service> services;
  final List<Doctor> doctors;

  factory ClinicPage.fromJson(Map<String, dynamic> json) => ClinicPage(
        clinic: Clinic.fromJson(json),
        services: [
          for (final s in json['services'] as List<dynamic>? ?? const [])
            Service.fromJson(s as Map<String, dynamic>),
        ],
        doctors: [
          for (final d in json['doctors'] as List<dynamic>? ?? const [])
            Doctor.fromJson(d as Map<String, dynamic>),
        ],
      );
}
