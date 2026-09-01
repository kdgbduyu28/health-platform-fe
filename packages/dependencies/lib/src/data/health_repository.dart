import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/appointment.dart';
import '../models/appointment_status.dart';
import '../models/clinic.dart';
import '../models/clinic_type.dart';
import '../models/doctor.dart';
import '../models/patient.dart';
import '../models/profile.dart';
import '../models/service.dart';

/// Every Supabase call the apps make lives here.
///
/// Nothing in this class filters by role or clinic. It does not need to: the
/// Row Level Security policies in health-platform-be already scope each query
/// to what the signed-in user may see, so `select()` returns a patient's own
/// appointments, a doctor's clinic's appointments, or nothing at all, purely
/// from who is holding the session.
class HealthRepository {
  HealthRepository(this._db);

  final SupabaseClient _db;

  /// Embeds needed to build an [Appointment]. The FK names are unambiguous
  /// because migration 20260818100000 removed the duplicate relationships.
  static const _appointmentSelect =
      '*, clinic:clinics(type), patient:patients(*), '
      'doctor:doctors(*, clinic:clinics(type))';

  // ── Reads ─────────────────────────────────────────────────────────────────

  Future<List<Clinic>> fetchClinics() async {
    final rows = await _db.from('clinics').select();
    return rows.map((r) => Clinic.fromJson(r)).toList();
  }

  Future<Profile?> fetchMyProfile() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return null;
    final row =
        await _db.from('profiles').select().eq('id', uid).maybeSingle();
    return row == null ? null : Profile.fromJson(row);
  }

  /// The patient chart belonging to the signed-in account, if one is linked.
  Future<Patient?> fetchMyPatient() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return null;
    final row = await _db
        .from('patients')
        .select()
        .eq('profile_id', uid)
        .maybeSingle();
    return row == null ? null : Patient.fromJson(row);
  }

  /// The roster row for a signed-in doctor, if one is linked.
  Future<Doctor?> fetchMyDoctor() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return null;
    final row = await _db
        .from('doctors')
        .select('*, clinic:clinics(type)')
        .eq('profile_id', uid)
        .maybeSingle();
    return row == null ? null : Doctor.fromJson(row);
  }

  Future<List<Appointment>> fetchAppointments() async {
    final rows = await _db
        .from('appointments')
        .select(_appointmentSelect)
        .order('scheduled_at', ascending: true);
    return rows.map((r) => Appointment.fromJson(r)).toList();
  }

  Future<List<Doctor>> fetchDoctors(String clinicId) async {
    final rows = await _db
        .from('doctors')
        .select('*, clinic:clinics(type)')
        .eq('clinic_id', clinicId)
        .eq('is_active', true)
        .order('full_name');
    return rows.map((r) => Doctor.fromJson(r)).toList();
  }

  Future<List<Service>> fetchServices(String clinicId) async {
    final rows = await _db
        .from('services')
        .select()
        .eq('clinic_id', clinicId)
        .eq('is_active', true)
        .order('name');
    return rows.map((r) => Service.fromJson(r)).toList();
  }

  Future<List<Patient>> fetchPatients() async {
    final rows = await _db.from('patients').select().order('full_name');
    return rows.map((r) => Patient.fromJson(r)).toList();
  }

  // ── Writes ────────────────────────────────────────────────────────────────

  /// Books an appointment.
  ///
  /// [status] is left at pending for patient bookings — RLS rejects anything
  /// else from a patient — while staff may pass `confirmed` for a walk-in.
  Future<void> book({
    required String clinicId,
    required String patientId,
    required String doctorId,
    required String serviceName,
    required DateTime scheduledAt,
    String? serviceId,
    AppointmentStatus status = AppointmentStatus.pending,
  }) async {
    await _db.from('appointments').insert({
      'clinic_id': clinicId,
      'patient_id': patientId,
      'doctor_id': doctorId,
      'service_id': serviceId,
      'service_name': serviceName,
      'scheduled_at': scheduledAt.toUtc().toIso8601String(),
      'status': status.wire,
    });
  }

  Future<void> updateStatus(String appointmentId, AppointmentStatus status) =>
      _db
          .from('appointments')
          .update({'status': status.wire}).eq('id', appointmentId);

  Future<void> updateNotes(String appointmentId, String notes) =>
      _db.from('appointments').update({'notes': notes}).eq('id', appointmentId);

  /// Registers a walk-in. [clinicId] is mandatory — RLS requires the record be
  /// stamped with a clinic the caller actually staffs, which is also what makes
  /// the row readable back to them straight away.
  Future<Patient> createWalkInPatient({
    required String clinicId,
    required String fullName,
    required String phone,
    String? email,
  }) async {
    final row = await _db
        .from('patients')
        .insert({
          'registered_clinic_id': clinicId,
          'full_name': fullName,
          'phone': phone,
          if (email != null && email.isNotEmpty) 'email': email,
        })
        .select()
        .single();
    return Patient.fromJson(row);
  }

  Future<void> updateMyProfile({String? fullName, String? phone}) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return;
    await _db.from('profiles').update({
      if (fullName != null) 'full_name': fullName,
      if (phone != null) 'phone': phone,
    }).eq('id', uid);
  }

  // ── Auth ──────────────────────────────────────────────────────────────────

  Future<void> signIn(String email, String password) =>
      _db.auth.signInWithPassword(email: email, password: password);

  Future<void> signUp(String email, String password, String fullName) =>
      _db.auth.signUp(
        email: email,
        password: password,
        data: {'full_name': fullName},
      );

  Future<void> signOut() => _db.auth.signOut();
}

/// Maps a [ClinicType] onto its database row.
extension ClinicLookup on List<Clinic> {
  Clinic? byType(ClinicType type) {
    for (final c in this) {
      if (c.type == type) return c;
    }
    return null;
  }
}
