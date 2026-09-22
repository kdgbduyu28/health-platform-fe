import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_notification.dart';
import '../models/app_role.dart';
import '../models/appointment.dart';
import '../models/appointment_status.dart';
import '../models/clinic.dart';
import '../models/clinic_page.dart';
import '../models/clinical_note.dart';
import '../models/doctor.dart';
import '../models/invoice.dart';
import '../models/membership.dart';
import '../models/patient.dart';
import '../models/profile.dart';
import '../models/service.dart';
import '../models/staff_invite.dart';
import '../models/time_off.dart';

/// Every Supabase call the apps make lives here.
///
/// Nothing in this class decides what a user is ALLOWED to see. Row Level
/// Security in health-platform-be already scopes each query to the signed-in
/// user: their own charts, the clinics they belong to, and nothing of any other
/// tenant. The clinic filters that do appear below only pick ONE clinic out of
/// several a user legitimately belongs to.
class HealthRepository {
  HealthRepository(this._db, {Future<void> Function()? beforeSignOut})
      : _beforeSignOut = beforeSignOut;

  final SupabaseClient _db;

  /// Runs while the session still exists: forgetting this browser's push
  /// subscription needs the account it belongs to.
  final Future<void> Function()? _beforeSignOut;

  static const _clinicSelect =
      '*, clinic_type:clinic_types(display_name, icon_name)';

  static const _patientSelect = '*, person:persons(*)';

  /// Each embed has exactly one foreign key behind it — PostgREST refuses to
  /// embed across two (PGRST201), which is why the migrations drop redundant
  /// single-column FKs whenever they add a composite one.
  static const _appointmentSelect =
      '*, patient:patients(*, person:persons(*)), doctor:doctors(*)';

  static const _invoiceSelect = '*, items:invoice_items(*), payments(*), '
      'patient:patients(*, person:persons(*)), '
      'appointment:appointments(service_name, scheduled_at)';

  static const _historySelect =
      '$_appointmentSelect, visit_note:visit_notes(*)';

  String? get _uid => _db.auth.currentUser?.id;

  // ── Reads ─────────────────────────────────────────────────────────────────

  /// Every clinic this user belongs to, as staff or as a patient. RLS does the
  /// scoping; a signed-in user attached to nothing gets an empty list.
  Future<List<Clinic>> fetchClinics() async {
    final rows = await _db.from('clinics').select(_clinicSelect).order('name');
    return rows.map((r) => Clinic.fromJson(r)).toList();
  }

  /// The public page of the active clinic at [slug], or null if there is none.
  /// Works signed out: it is the only thing `anon` may read.
  Future<ClinicPage?> fetchClinicPage(String slug) async {
    final row = await _db.rpc('clinic_by_slug', params: {'p_slug': slug});
    return row == null
        ? null
        : ClinicPage.fromJson(row as Map<String, dynamic>);
  }

  Future<Profile?> fetchMyProfile() async {
    final uid = _uid;
    if (uid == null) return null;
    final row =
        await _db.from('profiles').select().eq('id', uid).maybeSingle();
    return row == null ? null : Profile.fromJson(row);
  }

  /// The signed-in account's staff roles, one per clinic.
  Future<List<ClinicMembership>> fetchMyMemberships() async {
    final uid = _uid;
    if (uid == null) return const [];
    final rows = await _db
        .from('clinic_memberships')
        .select('profile_id, clinic_id, role, branch_locked')
        .eq('profile_id', uid);
    return rows.map((r) => ClinicMembership.fromJson(r)).toList();
  }

  /// Every chart the signed-in account holds — one per clinic joined.
  ///
  /// Two steps rather than one filtered embed: staff can also read the charts
  /// at their clinics, so "patients I can see" is not "my charts". Filtering on
  /// the person's account link is what separates the two.
  Future<List<Patient>> fetchMyPatients() async {
    final uid = _uid;
    if (uid == null) return const [];
    final person = await _db
        .from('persons')
        .select('id')
        .eq('profile_id', uid)
        .maybeSingle();
    if (person == null) return const [];
    final rows = await _db
        .from('patients')
        .select(_patientSelect)
        .eq('person_id', person['id'] as String);
    return rows.map((r) => Patient.fromJson(r)).toList();
  }

  /// Roster rows linked to the signed-in account — one per clinic they
  /// practise at.
  Future<List<Doctor>> fetchMyDoctors() async {
    final uid = _uid;
    if (uid == null) return const [];
    final rows = await _db.from('doctors').select().eq('profile_id', uid);
    return rows.map((r) => Doctor.fromJson(r)).toList();
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
        .select()
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

  /// The times [doctorId] can still take a [serviceId]-long visit on [day]
  /// (the clinic's calendar day), from `public.available_slots`: working
  /// days only, nobody's leave, nothing past, nothing overlapping.
  ///
  /// [ignoreAppointmentId] leaves one visit out — the one being moved — so
  /// it does not block the times around its own.
  Future<List<DateTime>> fetchAvailableSlots({
    required String doctorId,
    required DateTime day,
    String? serviceId,
    String? ignoreAppointmentId,
  }) async {
    final rows = await _db.rpc('available_slots', params: {
      'p_doctor_id': doctorId,
      'p_date': _date(day),
      'p_service_id': serviceId,
      if (ignoreAppointmentId != null) 'p_ignore': ignoreAppointmentId,
    }) as List<dynamic>;
    return [for (final t in rows) DateTime.parse(t as String).toLocal()];
  }

  /// The whole roster at [clinicId], inactive doctors included. Admin view.
  Future<List<Doctor>> fetchRoster(String clinicId) async {
    final rows = await _db
        .from('doctors')
        .select()
        .eq('clinic_id', clinicId)
        .order('full_name');
    return rows.map((r) => Doctor.fromJson(r)).toList();
  }

  /// The whole catalogue at [clinicId], retired services included. Admin view.
  Future<List<Service>> fetchCatalogue(String clinicId) async {
    final rows = await _db
        .from('services')
        .select()
        .eq('clinic_id', clinicId)
        .order('name');
    return rows.map((r) => Service.fromJson(r)).toList();
  }

  /// Leave and closures at [clinicId] that have not ended yet. Staff only.
  Future<List<TimeOff>> fetchTimeOff(String clinicId) async {
    final rows = await _db
        .from('doctor_time_off')
        .select()
        .eq('clinic_id', clinicId)
        .gte('ends_on', _date(DateTime.now()))
        .order('starts_on');
    return rows.map((r) => TimeOff.fromJson(r)).toList();
  }

  /// The charts held at [clinicId], sorted by name. Sorted here because
  /// ordering by an embedded column orders the embed, not the charts.
  Future<List<Patient>> fetchPatients(String clinicId) async {
    final rows = await _db
        .from('patients')
        .select(_patientSelect)
        .eq('clinic_id', clinicId);
    return rows.map((r) => Patient.fromJson(r)).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  /// One chart, with its person. Null if it does not exist or RLS hides it.
  Future<Patient?> fetchPatient(String patientId) async {
    final row = await _db
        .from('patients')
        .select(_patientSelect)
        .eq('id', patientId)
        .maybeSingle();
    return row == null ? null : Patient.fromJson(row);
  }

  /// Every appointment on one chart, newest first.
  ///
  /// With [withVisitNotes] each one carries its consultation note. Ask for
  /// that only as a clinician: RLS returns no notes to anyone else, so the
  /// embed would come back empty and look like "no notes written".
  Future<List<Appointment>> fetchPatientHistory(
    String patientId, {
    bool withVisitNotes = false,
  }) async {
    final rows = await _db
        .from('appointments')
        .select(withVisitNotes ? _historySelect : _appointmentSelect)
        .eq('patient_id', patientId)
        .order('scheduled_at', ascending: false);
    return rows.map((r) => Appointment.fromJson(r)).toList();
  }

  /// The standing medical note on a chart. Clinicians only.
  Future<ClinicalNote?> fetchChartNote(String patientId) async {
    final row = await _db
        .from('chart_notes')
        .select()
        .eq('patient_id', patientId)
        .maybeSingle();
    return ClinicalNote.fromNullableJson(row);
  }

  /// The consultation note on one appointment. Clinicians only.
  Future<ClinicalNote?> fetchVisitNote(String appointmentId) async {
    final row = await _db
        .from('visit_notes')
        .select()
        .eq('appointment_id', appointmentId)
        .maybeSingle();
    return ClinicalNote.fromNullableJson(row);
  }

  /// Everyone on staff at [clinicId], with their name and email. Readable by
  /// the clinic's admins.
  Future<List<ClinicMembership>> fetchStaff(String clinicId) async {
    final rows = await _db
        .from('clinic_memberships')
        .select(
            'profile_id, clinic_id, role, branch_locked, profile:profiles(full_name, email)')
        .eq('clinic_id', clinicId);
    return rows.map((r) => ClinicMembership.fromJson(r)).toList()
      ..sort((a, b) => (a.fullName ?? '').compareTo(b.fullName ?? ''));
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

  /// Moves a visit that has not started to [scheduledAt] — and, for staff,
  /// to [doctorId]. A patient may take only an offered time, and their visit
  /// goes back to pending for the clinic to confirm; staff keep its status.
  Future<void> reschedule(
    String appointmentId,
    DateTime scheduledAt, {
    String? doctorId,
  }) =>
      _db.rpc('reschedule_appointment', params: {
        'p_appointment_id': appointmentId,
        'p_scheduled_at': scheduledAt.toUtc().toIso8601String(),
        'p_doctor_id': doctorId,
      });

  /// Sets the note the patient reads on this appointment; blank clears it.
  /// The database lets only the clinic's doctors and admins change it.
  Future<void> updatePatientNote(String appointmentId, String? note) {
    final text = note?.trim() ?? '';
    return _db
        .from('appointments')
        .update({'patient_note': text.isEmpty ? null : text}).eq(
            'id', appointmentId);
  }

  /// Writes the standing medical note on a chart. An empty [body] clears it;
  /// the row stays, so who cleared it is still on record. Clinicians only.
  Future<void> saveChartNote({
    required String patientId,
    required String clinicId,
    required String body,
  }) =>
      _db.from('chart_notes').upsert(
        {'patient_id': patientId, 'clinic_id': clinicId, 'body': body},
        onConflict: 'patient_id',
      );

  /// Writes the consultation note on an appointment. Clinicians only.
  Future<void> saveVisitNote({
    required String appointmentId,
    required String clinicId,
    required String body,
  }) =>
      _db.from('visit_notes').upsert(
        {'appointment_id': appointmentId, 'clinic_id': clinicId, 'body': body},
        onConflict: 'appointment_id',
      );

  /// Registers a walk-in and books their appointment in one transaction,
  /// returning the new appointment id.
  ///
  /// The `book_walk_in` function creates the person, their chart at this
  /// clinic, and the appointment together, so losing the double-booking race
  /// leaves nothing half-made behind. It is SECURITY INVOKER, so RLS still
  /// decides whether this caller may register a patient at this clinic at all.
  Future<String> bookWalkIn({
    required String clinicId,
    required String fullName,
    required String phone,
    required String doctorId,
    required String serviceName,
    required DateTime scheduledAt,
    String? serviceId,
    String? email,
  }) async {
    final id = await _db.rpc('book_walk_in', params: {
      'p_clinic_id': clinicId,
      'p_full_name': fullName,
      'p_phone': phone,
      'p_doctor_id': doctorId,
      'p_service_name': serviceName,
      'p_scheduled_at': scheduledAt.toUtc().toIso8601String(),
      'p_service_id': serviceId,
      'p_email': email,
    });
    return id as String;
  }

  // ── Roster, catalogue and time off (admins; a doctor their own schedule) ──

  /// Adds a doctor to [clinicId]'s roster.
  Future<void> addDoctor({
    required String clinicId,
    required String name,
    required String specialty,
    required List<int> weekdays,
    required List<String> timeSlots,
  }) =>
      _db.from('doctors').insert({
        'clinic_id': clinicId,
        'full_name': name,
        'specialty': specialty,
        'available_weekdays': weekdays,
        'available_time_slots': timeSlots,
      });

  /// Changes a roster row. The database lets a doctor change only their own
  /// weekdays and time slots; everything else is the admin's.
  Future<void> updateDoctor(String doctorId, Map<String, Object?> changes) =>
      _db.from('doctors').update(changes).eq('id', doctorId);

  Future<void> addService({
    required String clinicId,
    required String name,
    required int durationMinutes,
    double? price,
  }) =>
      _db.from('services').insert({
        'clinic_id': clinicId,
        'name': name,
        'duration_minutes': durationMinutes,
        'price': price,
      });

  /// Services are retired (`is_active: false`), never deleted: past visits
  /// point at them.
  Future<void> updateService(String serviceId, Map<String, Object?> changes) =>
      _db.from('services').update(changes).eq('id', serviceId);

  /// Books leave for [doctorId], or closes the whole clinic when it is null.
  Future<void> addTimeOff({
    required String clinicId,
    String? doctorId,
    required DateTime startsOn,
    required DateTime endsOn,
    String? reason,
  }) =>
      _db.from('doctor_time_off').insert({
        'clinic_id': clinicId,
        'doctor_id': doctorId,
        'starts_on': _date(startsOn),
        'ends_on': _date(endsOn),
        'reason': (reason?.trim().isEmpty ?? true) ? null : reason!.trim(),
      });

  Future<void> deleteTimeOff(String id) =>
      _db.from('doctor_time_off').delete().eq('id', id);

  Future<void> updateMyProfile({String? fullName, String? phone}) async {
    final uid = _uid;
    if (uid == null) return;
    await _db.from('profiles').update({
      if (fullName != null) 'full_name': fullName,
      if (phone != null) 'phone': phone,
    }).eq('id', uid);
  }

  // ── Billing ───────────────────────────────────────────────────────────────
  // The database computes every total and moves every status; see
  // 20260924120100_billing. The front desk and admins write, other staff
  // read, a patient reads their own bills once issued.

  /// Bills at [clinicId], newest first.
  Future<List<Invoice>> fetchInvoices(String clinicId) async {
    final rows = await _db
        .from('invoices')
        .select(_invoiceSelect)
        .eq('clinic_id', clinicId)
        .order('created_at', ascending: false)
        .limit(300);
    return rows.map((r) => Invoice.fromJson(r)).toList();
  }

  /// Bills on one chart, newest first. For a patient, RLS already leaves
  /// out drafts.
  Future<List<Invoice>> fetchPatientInvoices(String patientId) async {
    final rows = await _db
        .from('invoices')
        .select(_invoiceSelect)
        .eq('patient_id', patientId)
        .order('created_at', ascending: false);
    return rows.map((r) => Invoice.fromJson(r)).toList();
  }

  Future<Invoice?> fetchInvoice(String invoiceId) async {
    final row = await _db
        .from('invoices')
        .select(_invoiceSelect)
        .eq('id', invoiceId)
        .maybeSingle();
    return row == null ? null : Invoice.fromJson(row);
  }

  /// The visit's live bill — not a voided one — or null.
  Future<Invoice?> fetchAppointmentInvoice(String appointmentId) async {
    final row = await _db
        .from('invoices')
        .select(_invoiceSelect)
        .eq('appointment_id', appointmentId)
        .neq('status', InvoiceStatus.voided.wire)
        .maybeSingle();
    return row == null ? null : Invoice.fromJson(row);
  }

  /// A draft for the visit with its service as the first line, or its
  /// existing bill. Returns the bill's id.
  Future<String> createInvoiceForAppointment(String appointmentId) async {
    final id = await _db.rpc('create_invoice_for_appointment',
        params: {'p_appointment_id': appointmentId});
    return id as String;
  }

  /// An empty draft for a chart, not tied to a visit.
  Future<String> createInvoice({
    required String clinicId,
    required String patientId,
  }) async {
    final row = await _db
        .from('invoices')
        .insert({'clinic_id': clinicId, 'patient_id': patientId})
        .select('id')
        .single();
    return row['id'] as String;
  }

  Future<void> addInvoiceItem({
    required String invoiceId,
    required String clinicId,
    required String description,
    required double unitPrice,
    int quantity = 1,
    String? serviceId,
  }) =>
      _db.from('invoice_items').insert({
        'invoice_id': invoiceId,
        'clinic_id': clinicId,
        'description': description.trim(),
        'unit_price': unitPrice,
        'quantity': quantity,
        'service_id': serviceId,
      });

  Future<void> updateInvoiceItem(
    String itemId, {
    required String description,
    required double unitPrice,
    required int quantity,
  }) =>
      _db.from('invoice_items').update({
        'description': description.trim(),
        'unit_price': unitPrice,
        'quantity': quantity,
      }).eq('id', itemId);

  Future<void> deleteInvoiceItem(String itemId) =>
      _db.from('invoice_items').delete().eq('id', itemId);

  /// The discount on a draft. Zero clears it.
  Future<void> setInvoiceDiscount(
    String invoiceId, {
    required double amount,
    String? reason,
  }) =>
      _db.from('invoices').update({
        'discount_amount': amount,
        'discount_reason':
            amount == 0 || (reason?.trim().isEmpty ?? true) ? null : reason!.trim(),
      }).eq('id', invoiceId);

  Future<void> setInvoiceNotes(String invoiceId, String? notes) =>
      _db.from('invoices').update({
        'notes': (notes?.trim().isEmpty ?? true) ? null : notes!.trim(),
      }).eq('id', invoiceId);

  /// Numbers and locks the bill; returns its number.
  Future<String> issueInvoice(String invoiceId) async {
    final number =
        await _db.rpc('issue_invoice', params: {'p_invoice_id': invoiceId});
    return number as String;
  }

  Future<void> voidInvoice(String invoiceId, String reason) => _db.rpc(
      'void_invoice',
      params: {'p_invoice_id': invoiceId, 'p_reason': reason});

  /// Drafts only; the database refuses the rest.
  Future<void> deleteInvoice(String invoiceId) =>
      _db.from('invoices').delete().eq('id', invoiceId);

  Future<void> recordPayment({
    required String invoiceId,
    required String clinicId,
    required double amount,
    required PaymentMethod method,
    String? reference,
  }) =>
      _db.from('payments').insert({
        'invoice_id': invoiceId,
        'clinic_id': clinicId,
        'amount': amount,
        'method': method.wire,
        'reference': (reference?.trim().isEmpty ?? true) ? null : reference!.trim(),
      });

  /// Admins only.
  Future<void> voidPayment(String paymentId, String reason) => _db.rpc(
      'void_payment',
      params: {'p_payment_id': paymentId, 'p_reason': reason});

  Future<BillingSummary> fetchBillingSummary(
    String clinicId, {
    required DateTime from,
    required DateTime to,
  }) async {
    final row = await _db.rpc('billing_summary', params: {
      'p_clinic_id': clinicId,
      'p_from': _date(from),
      'p_to': _date(to),
    });
    return BillingSummary.fromJson(row as Map<String, dynamic>);
  }

  // ── Notifications ─────────────────────────────────────────────────────────

  /// The signed-in account's inbox, newest first, live over Realtime. RLS
  /// sends each account only its own rows; [app] picks this app's.
  Stream<List<AppNotification>> watchNotifications(AppRole app) {
    final uid = _uid;
    if (uid == null) return Stream.value(const []);
    return _db
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('profile_id', uid)
        .order('created_at')
        .limit(100)
        .map((rows) => [
              for (final r in rows)
                if (r['app'] == app.wire) AppNotification.fromJson(r),
            ]);
  }

  /// Marks [ids] read; with none given, everything unread in [app].
  Future<void> markNotificationsRead(AppRole app, {List<String>? ids}) {
    var q = _db
        .from('notifications')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('app', app.wire)
        .isFilter('read_at', null);
    if (ids != null) q = q.inFilter('id', ids);
    return q;
  }

  /// Registers this browser for [app]'s pushes to the signed-in account.
  Future<void> savePushSubscription({
    required AppRole app,
    required String endpoint,
    required String p256dh,
    required String auth,
    String? userAgent,
  }) =>
      _db.rpc('save_push_subscription', params: {
        'p_app': app.wire,
        'p_endpoint': endpoint,
        'p_p256dh': p256dh,
        'p_auth': auth,
        'p_user_agent': userAgent,
      });

  Future<void> deletePushSubscription(String endpoint) => _db
      .rpc('delete_push_subscription', params: {'p_endpoint': endpoint});

  // ── Onboarding ────────────────────────────────────────────────────────────

  /// Attaches the signed-in account to the clinic with this code, creating
  /// their chart there. Returns the clinic id. Safe to repeat.
  Future<String> joinClinic(String code) async {
    final id = await _db.rpc('join_clinic', params: {'p_join_code': code});
    return id as String;
  }

  /// Grants [role] at [clinicId] to the account registered under [email].
  /// Admin-only; the account must already exist. [branchLocked] makes an
  /// admin a branch admin, and only a full admin may grant either kind.
  Future<void> inviteStaff({
    required String clinicId,
    required String email,
    required AppRole role,
    bool branchLocked = false,
  }) =>
      _db.rpc('invite_staff', params: {
        'p_clinic_id': clinicId,
        'p_email': email,
        'p_role': role.wire,
        'p_branch_locked': branchLocked,
      });

  Future<void> removeStaff({
    required String clinicId,
    required String profileId,
  }) =>
      _db.rpc('remove_staff', params: {
        'p_clinic_id': clinicId,
        'p_profile_id': profileId,
      });

  /// Updates the clinic's own presentation and contact details. The database
  /// only lets an admin write those columns — name, logo, colour, contact,
  /// timezone, join code — and not the clinic's type, slug or active status.
  Future<void> updateClinic(String clinicId, Map<String, Object?> changes) =>
      _db.from('clinics').update(changes).eq('id', clinicId);

  /// Issues a fresh join code, invalidating the old one. Returns the new code.
  Future<String> rotateJoinCode(String clinicId) async {
    final code =
        await _db.rpc('rotate_join_code', params: {'p_clinic_id': clinicId});
    return code as String;
  }

  // ── Staff codes ───────────────────────────────────────────────────────────

  /// Every staff code issued at [clinicId] and what became of it, newest
  /// first. Readable by the clinic's admins, branch admins included.
  Future<List<StaffInvite>> fetchStaffInvites(String clinicId) async {
    final rows = await _db
        .from('staff_invites')
        .select()
        .eq('clinic_id', clinicId)
        .order('created_at', ascending: false);
    return rows.map((r) => StaffInvite.fromJson(r)).toList();
  }

  /// Issues a single-use code for one doctor or assistant.
  Future<StaffInvite> createStaffInvite({
    required String clinicId,
    required AppRole role,
    String? label,
  }) async {
    final row = await _db.rpc('create_staff_invite', params: {
      'p_clinic_id': clinicId,
      'p_role': role.wire,
      'p_label': label,
    });
    return StaffInvite.fromJson(row as Map<String, dynamic>);
  }

  Future<void> revokeStaffInvite(String inviteId) =>
      _db.rpc('revoke_staff_invite', params: {'p_invite_id': inviteId});

  /// Approves or rejects a request. Approving a doctor needs either an
  /// unlinked roster entry at the clinic ([doctorId]) or a [specialty] to
  /// create one with.
  Future<void> decideStaffRequest({
    required String inviteId,
    required bool approve,
    String? doctorId,
    String? specialty,
  }) =>
      _db.rpc('decide_staff_request', params: {
        'p_invite_id': inviteId,
        'p_approve': approve,
        'p_doctor_id': doctorId,
        'p_specialty': specialty,
      });

  /// Files a request to join a clinic as [app] — the app the code was typed
  /// into. Grants nothing until an admin approves.
  Future<void> redeemStaffInvite(String code, AppRole app) =>
      _db.rpc('redeem_staff_invite', params: {
        'p_code': code,
        'p_app_role': app.wire,
      });

  /// The signed-in account's own requests, newest first.
  Future<List<StaffRequest>> fetchMyStaffRequests() async {
    if (_uid == null) return const [];
    final rows = await _db.rpc('my_staff_requests') as List<dynamic>;
    return rows
        .map((r) => StaffRequest.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  // ── Auth ──────────────────────────────────────────────────────────────────

  Future<void> signIn(String email, String password) =>
      _db.auth.signInWithPassword(email: email, password: password);

  /// Emails a one-time recovery code. Supabase answers the same whether or not
  /// the address has an account, so this reveals nothing about who signed up.
  ///
  /// The email must show `{{ .Token }}`: the default template only has a link,
  /// and this app asks for the code instead (see the backend README).
  Future<void> sendPasswordResetCode(String email) =>
      _db.auth.resetPasswordForEmail(email.trim());

  /// Exchanges the emailed code for a session, then sets the new password.
  ///
  /// Verifying signs the user in. That is why these are two steps the caller
  /// can drive separately: if the password update fails after a good code, a
  /// retry must not spend the code a second time.
  Future<void> verifyPasswordResetCode(String email, String code) =>
      _db.auth.verifyOTP(
        email: email.trim(),
        token: code.trim(),
        type: OtpType.recovery,
      );

  /// Sets a new password for the signed-in account.
  Future<void> changePassword(String newPassword) =>
      _db.auth.updateUser(UserAttributes(password: newPassword));

  /// Creates an account and nothing else. Access is granted separately: a
  /// patient joins a clinic with its code, staff are added by a clinic admin.
  Future<void> signUp(String email, String password, String fullName) =>
      _db.auth.signUp(
        email: email,
        password: password,
        data: {'full_name': fullName},
      );

  /// Signs out — after unhooking this browser's push notifications, so the
  /// next person to use it does not receive this account's. That step never
  /// holds up signing out.
  Future<void> signOut() async {
    try {
      await _beforeSignOut?.call().timeout(const Duration(seconds: 3));
    } catch (_) {}
    await _db.auth.signOut();
  }
}

/// `2026-09-23` — a calendar day, as Postgres `date` takes it.
String _date(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';
