import type { PostgrestError, SupabaseClient } from '@supabase/supabase-js';

import { SupabaseConfig } from '../config/supabase_config';
import { AppNotification } from '../models/app_notification';
import type { AppRole } from '../models/app_role';
import { Appointment } from '../models/appointment';
import type { AppointmentStatus } from '../models/appointment_status';
import { Clinic } from '../models/clinic';
import { ClinicPage } from '../models/clinic_page';
import { ClinicalNote } from '../models/clinical_note';
import { type ImportKind, ImportBatch, ImportRowResult, type UndoImportResult } from '../models/data_import';
import { type DentalCode, type DentalEntryStatus, DentalEntry, type ToothSurface } from '../models/dental_chart';
import { Doctor } from '../models/doctor';
import { BillingSummary, Invoice, type PaymentMethod } from '../models/invoice';
import { LedgerEntry, LedgerSummary } from '../models/ledger';
import { ClinicMembership } from '../models/membership';
import { Patient, type PatientFlag, PatientPage, type PatientSort } from '../models/patient';
import { type IntakeSource, type IntakeSubmission, PatientIntake } from '../models/patient_intake';
import { Profile } from '../models/profile';
import { Service } from '../models/service';
import { StaffInvite, StaffRequest } from '../models/staff_invite';
import { TimeOff } from '../models/time_off';
import { formatDay } from '../util/dates';

type Json = Record<string, any>;

/// A failed database call. Carries PostgREST's code (`P0001` for a message
/// the database wrote for people, `23505` for a unique violation…) so
/// `describeError` can pick the right words.
export class DatabaseError extends Error {
  constructor(
    message: string,
    readonly code: string | null,
    readonly details: string | null = null,
    readonly hint: string | null = null,
  ) {
    super(message);
    this.name = 'DatabaseError';
  }

  static from(e: PostgrestError): DatabaseError {
    return new DatabaseError(e.message, e.code ?? null, e.details ?? null, e.hint ?? null);
  }
}

/// supabase-js reports failures in the result rather than throwing; every
/// call here throws instead, so a failed read reaches React Query as an error
/// and never as an empty list that looks like "nothing on file".
async function must<T>(query: PromiseLike<{ data: T; error: PostgrestError | null }>): Promise<T> {
  const { data, error } = await query;
  if (error) throw DatabaseError.from(error);
  return data;
}

/// Same, for a call whose answer nobody reads.
async function run(query: PromiseLike<{ error: PostgrestError | null }>): Promise<void> {
  const { error } = await query;
  if (error) throw DatabaseError.from(error);
}

/// Throws Supabase Auth's error as it is: its message is already a sentence.
async function auth<T extends { error: unknown }>(call: Promise<T>): Promise<T> {
  const result = await call;
  if (result.error) throw result.error;
  return result;
}

function utc(d: Date): string {
  return d.toISOString();
}

function trimOrNull(s: string | null | undefined): string | null {
  const t = s?.trim() ?? '';
  return t === '' ? null : t;
}

/// Every Supabase call the apps make lives here.
///
/// Nothing in this class decides what a user is ALLOWED to see. Row Level
/// Security in health-platform-be already scopes each query to the signed-in
/// user: their own charts, the clinics they belong to, and nothing of any
/// other tenant. The clinic filters that do appear below only pick ONE clinic
/// out of several a user legitimately belongs to.
export class HealthRepository {
  constructor(
    private readonly db: SupabaseClient,
    /// Runs while the session still exists: forgetting this browser's push
    /// subscription needs the account it belongs to.
    private readonly beforeSignOut?: () => Promise<void>,
  ) {}

  private static readonly clinicSelect = '*, clinic_type:clinic_types(display_name, icon_name, chart_kind)';

  private static readonly patientSelect = '*, person:persons(*)';

  /// Each embed has exactly one foreign key behind it — PostgREST refuses to
  /// embed across two (PGRST201), which is why the migrations drop redundant
  /// single-column FKs whenever they add a composite one.
  private static readonly appointmentSelect = '*, patient:patients(*, person:persons(*)), doctor:doctors(*)';

  private static readonly invoiceSelect =
    '*, items:invoice_items(*), payments(*), ' +
    'patient:patients(*, person:persons(*)), ' +
    'appointment:appointments(service_name, scheduled_at, ' +
    'doctor:doctors(full_name))';

  private static readonly historySelect = `${HealthRepository.appointmentSelect}, visit_note:visit_notes(*)`;

  /// The Supabase client underneath, for the few reads that are not worth a
  /// method here (the calendar feed token, the activity log).
  get client(): SupabaseClient {
    return this.db;
  }

  private async uid(): Promise<string | null> {
    const { data } = await this.db.auth.getSession();
    return data.session?.user.id ?? null;
  }

  // ── Reads ─────────────────────────────────────────────────────────────────

  /// Every clinic this user belongs to, as staff or as a patient. RLS does
  /// the scoping; a signed-in user attached to nothing gets an empty list.
  async fetchClinics(): Promise<Clinic[]> {
    const rows = await must(this.db.from('clinics').select(HealthRepository.clinicSelect).order('name'));
    return (rows as Json[]).map(Clinic.fromJson);
  }

  /// The public page of the active clinic at [slug], or null if there is
  /// none. Works signed out: it is the only thing `anon` may read.
  async fetchClinicPage(slug: string): Promise<ClinicPage | null> {
    const row = await must(this.db.rpc('clinic_by_slug', { p_slug: slug }));
    return row == null ? null : ClinicPage.fromJson(row as Json);
  }

  async fetchMyProfile(): Promise<Profile | null> {
    const uid = await this.uid();
    if (uid == null) return null;
    const row = await must(this.db.from('profiles').select().eq('id', uid).maybeSingle());
    return row == null ? null : Profile.fromJson(row);
  }

  /// The signed-in account's staff roles, one per clinic.
  async fetchMyMemberships(): Promise<ClinicMembership[]> {
    const uid = await this.uid();
    if (uid == null) return [];
    const rows = await must(
      this.db.from('clinic_memberships').select('profile_id, clinic_id, role, branch_locked').eq('profile_id', uid),
    );
    return (rows as Json[]).map(ClinicMembership.fromJson);
  }

  /// Every chart the signed-in account holds — one per clinic joined.
  ///
  /// Two steps rather than one filtered embed: staff can also read the charts
  /// at their clinics, so "patients I can see" is not "my charts". Filtering
  /// on the person's account link is what separates the two.
  async fetchMyPatients(): Promise<Patient[]> {
    const uid = await this.uid();
    if (uid == null) return [];
    const person = await must(this.db.from('persons').select('id').eq('profile_id', uid).maybeSingle());
    if (person == null) return [];
    const rows = await must(
      this.db
        .from('patients')
        .select(`${HealthRepository.patientSelect}, intake:patient_intakes(updated_at)`)
        .eq('person_id', (person as Json).id),
    );
    return (rows as Json[]).map(Patient.fromJson);
  }

  /// Roster rows linked to the signed-in account — one per clinic they
  /// practise at.
  async fetchMyDoctors(): Promise<Doctor[]> {
    const uid = await this.uid();
    if (uid == null) return [];
    const rows = await must(this.db.from('doctors').select().eq('profile_id', uid));
    return (rows as Json[]).map(Doctor.fromJson);
  }

  /// The appointments the signed-in user may see from [since] on — the
  /// working set every screen filters. Older visits are read a page at a time
  /// with [fetchPastAppointments], so a clinic's years of history never load
  /// up front.
  async fetchAppointments(since: Date): Promise<Appointment[]> {
    const rows = await must(
      this.db
        .from('appointments')
        .select(HealthRepository.appointmentSelect)
        .gte('scheduled_at', utc(since))
        .order('scheduled_at', { ascending: true }),
    );
    return (rows as Json[]).map(Appointment.fromJson);
  }

  /// One appointment, however old. Null if it does not exist or RLS hides it.
  async fetchAppointment(id: string): Promise<Appointment | null> {
    const row = await must(
      this.db.from('appointments').select(HealthRepository.appointmentSelect).eq('id', id).maybeSingle(),
    );
    return row == null ? null : Appointment.fromJson(row);
  }

  /// Visits at [clinicId] that start in [from, to), oldest first — one
  /// calendar page, however far back. RLS still decides whose.
  async fetchAppointmentsBetween(clinicId: string, from: Date, to: Date): Promise<Appointment[]> {
    const rows = await must(
      this.db
        .from('appointments')
        .select(HealthRepository.appointmentSelect)
        .eq('clinic_id', clinicId)
        .gte('scheduled_at', utc(from))
        .lt('scheduled_at', utc(to))
        .order('scheduled_at', { ascending: true }),
    );
    return (rows as Json[]).map(Appointment.fromJson);
  }

  /// Visits at [clinicId] before [before], newest first: rows [offset] to
  /// [offset] + [limit] − 1. Narrowed to one doctor or one chart when given.
  async fetchPastAppointments(args: {
    clinicId: string;
    before: Date;
    doctorId?: string | null;
    patientId?: string | null;
    offset?: number;
    limit?: number;
  }): Promise<Appointment[]> {
    const offset = args.offset ?? 0;
    const limit = args.limit ?? 20;
    let q = this.db
      .from('appointments')
      .select(HealthRepository.appointmentSelect)
      .eq('clinic_id', args.clinicId)
      .lt('scheduled_at', utc(args.before));
    if (args.doctorId != null) q = q.eq('doctor_id', args.doctorId);
    if (args.patientId != null) q = q.eq('patient_id', args.patientId);
    const rows = await must(
      q.order('scheduled_at', { ascending: false }).order('id').range(offset, offset + limit - 1),
    );
    return (rows as Json[]).map(Appointment.fromJson);
  }

  async fetchDoctors(clinicId: string): Promise<Doctor[]> {
    const rows = await must(
      this.db.from('doctors').select().eq('clinic_id', clinicId).eq('is_active', true).order('full_name'),
    );
    return (rows as Json[]).map(Doctor.fromJson);
  }

  async fetchServices(clinicId: string): Promise<Service[]> {
    const rows = await must(
      this.db.from('services').select().eq('clinic_id', clinicId).eq('is_active', true).order('name'),
    );
    return (rows as Json[]).map(Service.fromJson);
  }

  /// The times [doctorId] can still take a [serviceId]-long visit on [day]
  /// (the clinic's calendar day), from `public.available_slots`: working days
  /// only, nobody's leave, nothing past, nothing overlapping.
  ///
  /// [ignoreAppointmentId] leaves one visit out — the one being moved — so it
  /// does not block the times around its own.
  async fetchAvailableSlots(args: {
    doctorId: string;
    day: Date;
    serviceId?: string | null;
    ignoreAppointmentId?: string | null;
  }): Promise<Date[]> {
    const rows = await must(
      this.db.rpc('available_slots', {
        p_doctor_id: args.doctorId,
        p_date: formatDay(args.day),
        p_service_id: args.serviceId ?? null,
        ...(args.ignoreAppointmentId != null ? { p_ignore: args.ignoreAppointmentId } : {}),
      }),
    );
    return ((rows ?? []) as string[]).map((t) => new Date(t));
  }

  /// The whole roster at [clinicId], inactive doctors included. Admin view.
  async fetchRoster(clinicId: string): Promise<Doctor[]> {
    const rows = await must(this.db.from('doctors').select().eq('clinic_id', clinicId).order('full_name'));
    return (rows as Json[]).map(Doctor.fromJson);
  }

  /// The whole catalogue at [clinicId], retired services included. Admin view.
  async fetchCatalogue(clinicId: string): Promise<Service[]> {
    const rows = await must(this.db.from('services').select().eq('clinic_id', clinicId).order('name'));
    return (rows as Json[]).map(Service.fromJson);
  }

  /// Leave and closures at [clinicId] that have not ended yet. Staff only.
  async fetchTimeOff(clinicId: string): Promise<TimeOff[]> {
    const rows = await must(
      this.db
        .from('doctor_time_off')
        .select()
        .eq('clinic_id', clinicId)
        .gte('ends_on', formatDay(new Date()))
        .order('starts_on'),
    );
    return (rows as Json[]).map(TimeOff.fromJson);
  }

  /// One page of the charts at [clinicId] matching [query] (name, email, or
  /// phone however typed) and carrying every one of [filters], sorted by
  /// [sort] (name by default), with each chart's visits, balance and remarks.
  /// Searched in the database: see `public.search_patients`.
  async searchPatients(
    clinicId: string,
    opts: {
      query?: string | null;
      offset?: number;
      limit?: number;
      filters?: ReadonlySet<PatientFlag>;
      sort?: PatientSort;
      descending?: boolean;
    } = {},
  ): Promise<PatientPage> {
    const filters = opts.filters ?? new Set<PatientFlag>();
    const sort = opts.sort ?? 'name';
    const row = await must(
      this.db.rpc('search_patients', {
        p_clinic_id: clinicId,
        p_query: opts.query ?? null,
        p_limit: opts.limit ?? 30,
        p_offset: opts.offset ?? 0,
        // Only when asked for, so the pickers keep working on a database
        // without them.
        ...(filters.size > 0 ? { p_filters: [...filters] } : {}),
        ...(sort !== 'name' ? { p_sort: sort } : {}),
        ...(opts.descending ? { p_desc: true } : {}),
      }),
    );
    return PatientPage.fromJson(row as Json);
  }

  /// One chart, with its person. Null if it does not exist or RLS hides it.
  async fetchPatient(patientId: string): Promise<Patient | null> {
    const row = await must(
      this.db.from('patients').select(HealthRepository.patientSelect).eq('id', patientId).maybeSingle(),
    );
    return row == null ? null : Patient.fromJson(row);
  }

  /// Every appointment on one chart, newest first.
  ///
  /// With [withVisitNotes] each one carries its consultation note. Ask for
  /// that only as a clinician: RLS returns no notes to anyone else, so the
  /// embed would come back empty and look like "no notes written".
  async fetchPatientHistory(patientId: string, withVisitNotes = false): Promise<Appointment[]> {
    const rows = await must(
      this.db
        .from('appointments')
        .select(withVisitNotes ? HealthRepository.historySelect : HealthRepository.appointmentSelect)
        .eq('patient_id', patientId)
        .order('scheduled_at', { ascending: false }),
    );
    return (rows as Json[]).map(Appointment.fromJson);
  }

  /// The standing medical note on a chart. Clinicians only.
  async fetchChartNote(patientId: string): Promise<ClinicalNote | null> {
    const row = await must(this.db.from('chart_notes').select().eq('patient_id', patientId).maybeSingle());
    return ClinicalNote.fromNullableJson(row);
  }

  /// The consultation note on one appointment. Clinicians only.
  async fetchVisitNote(appointmentId: string): Promise<ClinicalNote | null> {
    const row = await must(this.db.from('visit_notes').select().eq('appointment_id', appointmentId).maybeSingle());
    return ClinicalNote.fromNullableJson(row);
  }

  /// Every entry on a chart's dental chart, notes included. Staff at the
  /// clinic only; a patient reads theirs with [fetchMyDentalChart].
  async fetchDentalEntries(patientId: string): Promise<DentalEntry[]> {
    const rows = await must(
      this.db.from('dental_chart_entries').select().eq('patient_id', patientId).order('created_at'),
    );
    return (rows as Json[]).map(DentalEntry.fromJson);
  }

  /// The signed-in patient's own dental chart, without the clinic's notes.
  async fetchMyDentalChart(patientId: string): Promise<DentalEntry[]> {
    const rows = await must(this.db.rpc('patient_dental_chart', { p_patient_id: patientId }));
    return ((rows ?? []) as Json[]).map(DentalEntry.fromJson);
  }

  /// Everyone on staff at [clinicId], with their name and email. Readable by
  /// the clinic's admins.
  async fetchStaff(clinicId: string): Promise<ClinicMembership[]> {
    const rows = await must(
      this.db
        .from('clinic_memberships')
        .select('profile_id, clinic_id, role, branch_locked, profile:profiles(full_name, email)')
        .eq('clinic_id', clinicId),
    );
    return (rows as Json[])
      .map(ClinicMembership.fromJson)
      .sort((a, b) => (a.fullName ?? '').localeCompare(b.fullName ?? ''));
  }

  // ── Writes ────────────────────────────────────────────────────────────────

  /// Books an appointment.
  ///
  /// [status] is left at pending for patient bookings — RLS rejects anything
  /// else from a patient — while staff may pass `confirmed` for a walk-in.
  async book(args: {
    clinicId: string;
    patientId: string;
    doctorId: string;
    serviceName: string;
    scheduledAt: Date;
    serviceId?: string | null;
    status?: AppointmentStatus;
  }): Promise<void> {
    await run(
      this.db.from('appointments').insert({
        clinic_id: args.clinicId,
        patient_id: args.patientId,
        doctor_id: args.doctorId,
        service_id: args.serviceId ?? null,
        service_name: args.serviceName,
        scheduled_at: utc(args.scheduledAt),
        status: args.status ?? 'pending',
      }),
    );
  }

  /// Books a visit that already happened but was never entered, returning
  /// its id. It goes in confirmed, the furthest the database lets a new visit
  /// start; [completeRecordedVisit] takes it the rest of the way. Staff
  /// bookings notify nobody, and nothing stops a past time for staff.
  async recordPastVisit(args: {
    clinicId: string;
    patientId: string;
    doctorId: string;
    serviceName: string;
    scheduledAt: Date;
    serviceId?: string | null;
  }): Promise<string> {
    const row = await must(
      this.db
        .from('appointments')
        .insert({
          clinic_id: args.clinicId,
          patient_id: args.patientId,
          doctor_id: args.doctorId,
          service_id: args.serviceId ?? null,
          service_name: args.serviceName,
          scheduled_at: utc(args.scheduledAt),
          status: 'confirmed',
        })
        .select('id')
        .single(),
    );
    return (row as Json).id;
  }

  /// Walks a recorded visit from confirmed to completed. Anyone on staff may.
  /// The completed time is stamped as now.
  completeRecordedVisit(appointmentId: string): Promise<string | null> {
    return this.completeVisit(appointmentId);
  }

  /// Marks a visit done with the services performed — service id → how many
  /// times — and puts them on its draft bill at the catalogue price. Returns
  /// the visit's bill, or null when it has none (no services, no bill).
  /// Called again on a completed visit, it corrects the services.
  async completeVisit(appointmentId: string, services: ReadonlyMap<string, number> = new Map()): Promise<string | null> {
    const id = await must(
      this.db.rpc('complete_visit', {
        p_appointment_id: appointmentId,
        p_services: [...services.entries()].map(([serviceId, quantity]) => ({ service_id: serviceId, quantity })),
      }),
    );
    return (id as string | null) ?? null;
  }

  updateStatus(appointmentId: string, status: AppointmentStatus): Promise<void> {
    return run(this.db.from('appointments').update({ status }).eq('id', appointmentId));
  }

  /// Moves a visit that has not started to [scheduledAt] — and, for staff, to
  /// [doctorId]. A patient may take only an offered time, and their visit
  /// goes back to pending for the clinic to confirm; staff keep its status.
  reschedule(appointmentId: string, scheduledAt: Date, doctorId?: string | null): Promise<void> {
    return run(
      this.db.rpc('reschedule_appointment', {
        p_appointment_id: appointmentId,
        p_scheduled_at: utc(scheduledAt),
        p_doctor_id: doctorId ?? null,
      }),
    );
  }

  /// Sets the note the patient reads on this appointment; blank clears it.
  /// The database lets only the clinic's doctors and admins change it.
  updatePatientNote(appointmentId: string, note: string | null): Promise<void> {
    return run(this.db.from('appointments').update({ patient_note: trimOrNull(note) }).eq('id', appointmentId));
  }

  /// Writes the standing medical note on a chart. An empty [body] clears it;
  /// the row stays, so who cleared it is still on record. Clinicians only.
  saveChartNote(args: { patientId: string; clinicId: string; body: string }): Promise<void> {
    return run(
      this.db
        .from('chart_notes')
        .upsert({ patient_id: args.patientId, clinic_id: args.clinicId, body: args.body }, { onConflict: 'patient_id' }),
    );
  }

  /// Writes the consultation note on an appointment. Clinicians only.
  saveVisitNote(args: { appointmentId: string; clinicId: string; body: string }): Promise<void> {
    return run(
      this.db
        .from('visit_notes')
        .upsert(
          { appointment_id: args.appointmentId, clinic_id: args.clinicId, body: args.body },
          { onConflict: 'appointment_id' },
        ),
    );
  }

  /// Charts one thing about one tooth. Doctors and admins only; the database
  /// also refuses work marked done at a visit the patient did not attend.
  addDentalEntry(args: {
    clinicId: string;
    patientId: string;
    tooth: number;
    code: DentalCode;
    status: DentalEntryStatus;
    surfaces?: ReadonlySet<ToothSurface>;
    appointmentId?: string | null;
    note?: string | null;
  }): Promise<void> {
    return run(
      this.db.from('dental_chart_entries').insert({
        clinic_id: args.clinicId,
        patient_id: args.patientId,
        appointment_id: args.appointmentId ?? null,
        tooth: args.tooth,
        code: args.code,
        status: args.status,
        surfaces: [...(args.surfaces ?? [])],
        note: trimOrNull(args.note),
      }),
    );
  }

  /// Marks planned work done at [appointmentId].
  completeDentalEntry(entryId: string, appointmentId: string): Promise<void> {
    return run(
      this.db
        .from('dental_chart_entries')
        .update({ status: 'done', appointment_id: appointmentId })
        .eq('id', entryId),
    );
  }

  deleteDentalEntry(entryId: string): Promise<void> {
    return run(this.db.from('dental_chart_entries').delete().eq('id', entryId));
  }

  /// Registers a walk-in and books their appointment in one transaction,
  /// returning the new appointment id.
  ///
  /// The `book_walk_in` function creates the person, their chart at this
  /// clinic, and the appointment together, so losing the double-booking race
  /// leaves nothing half-made behind. It is SECURITY INVOKER, so RLS still
  /// decides whether this caller may register a patient at this clinic at
  /// all.
  async bookWalkIn(args: {
    clinicId: string;
    fullName: string;
    phone: string;
    doctorId: string;
    serviceName: string;
    scheduledAt: Date;
    serviceId?: string | null;
    email?: string | null;
  }): Promise<string> {
    const id = await must(
      this.db.rpc('book_walk_in', {
        p_clinic_id: args.clinicId,
        p_full_name: args.fullName,
        p_phone: args.phone,
        p_doctor_id: args.doctorId,
        p_service_name: args.serviceName,
        p_scheduled_at: utc(args.scheduledAt),
        p_service_id: args.serviceId ?? null,
        p_email: args.email ?? null,
      }),
    );
    return id as string;
  }

  // ── Patient information form ──────────────────────────────────────────────

  /// The form on file for one chart, or null if it was never filled in.
  async fetchIntake(patientId: string): Promise<PatientIntake | null> {
    const row = await must(this.db.from('patient_intakes').select().eq('patient_id', patientId).maybeSingle());
    return row == null ? null : PatientIntake.fromJson(row);
  }

  /// A new patient at [clinicId], with no visit booked: their person, their
  /// chart and (when given) their form in one transaction. Returns the chart
  /// id. Front desk and admins only; the database checks.
  async registerPatient(args: { clinicId: string; form: IntakeSubmission; source: IntakeSource }): Promise<string> {
    const id = await must(
      this.db.rpc('register_patient', {
        p_clinic_id: args.clinicId,
        p_person: args.form.person,
        p_intake: args.form.intake,
        p_source: args.source,
      }),
    );
    return id as string;
  }

  /// Saves the form for an existing chart — the patient's own, or one at the
  /// caller's clinic — updating the person's details with it.
  savePatientIntake(args: { patientId: string; form: IntakeSubmission; source: IntakeSource }): Promise<void> {
    return run(
      this.db.rpc('save_patient_intake', {
        p_patient_id: args.patientId,
        p_person: args.form.person,
        p_intake: args.form.intake,
        p_source: args.source,
      }),
    );
  }

  // ── Staff PIN (taking the front desk tablet back) ────────────────────────

  async hasStaffPin(): Promise<boolean> {
    return ((await must(this.db.rpc('has_staff_pin'))) as boolean | null) ?? false;
  }

  setStaffPin(pin: string): Promise<void> {
    return run(this.db.rpc('set_staff_pin', { p_pin: pin }));
  }

  /// True for the signed-in account's PIN. Throws once too many wrong ones
  /// have been tried, with the wait in the message.
  async verifyStaffPin(pin: string): Promise<boolean> {
    return ((await must(this.db.rpc('verify_staff_pin', { p_pin: pin }))) as boolean | null) ?? false;
  }

  // ── Patients, visits and dental charts in and out as CSV ─────────────────

  /// Starts recording an import of [fileName] at [clinicId]; the rows then go
  /// in with [importRows]. Returns the batch id.
  async startImport(args: { clinicId: string; fileName: string; kind?: ImportKind }): Promise<string> {
    return (await must(
      this.db.rpc('start_import', {
        p_clinic_id: args.clinicId,
        p_kind: args.kind ?? 'patients',
        p_file_name: args.fileName,
      }),
    )) as string;
  }

  /// Imports up to 500 rows (the JSON the `read…Row` functions make) of
  /// [kind] into [clinicId]: `import_patients`, `import_visits` or
  /// `import_dental`. Without [batchId] it is a dry run: every row is checked
  /// by the database and nothing is kept.
  async importRows(args: {
    kind: ImportKind;
    clinicId: string;
    rows: Json[];
    batchId?: string | null;
  }): Promise<ImportRowResult[]> {
    const out = await must(
      this.db.rpc(`import_${args.kind}`, {
        p_clinic_id: args.clinicId,
        p_rows: args.rows,
        p_batch_id: args.batchId ?? null,
      }),
    );
    return ((out ?? []) as Json[]).map(ImportRowResult.fromJson);
  }

  /// The clinic's imports, newest first.
  async fetchImportBatches(clinicId: string): Promise<ImportBatch[]> {
    const rows = await must(
      this.db
        .from('import_batches')
        .select()
        .eq('clinic_id', clinicId)
        .order('created_at', { ascending: false })
        .limit(20),
    );
    return (rows as Json[]).map(ImportBatch.fromJson);
  }

  /// Removes what an import added, if nothing has happened to it since.
  /// Throws, with the reason, otherwise.
  async undoImport(batchId: string): Promise<UndoImportResult> {
    const out = (await must(this.db.rpc('undo_import', { p_batch_id: batchId }))) as Json;
    return { removed: out?.removed ?? 0, keptUpdates: out?.kept_updates ?? 0 };
  }

  /// One page of [clinicId]'s [kind] for a file. The first page puts the
  /// export on the clinic's record. Clinical notes come back only for doctors
  /// and admins.
  async exportRows(kind: ImportKind, clinicId: string, opts: { limit?: number; offset?: number } = {}): Promise<Json[]> {
    const out = await must(
      this.db.rpc(`export_${kind}`, {
        p_clinic_id: clinicId,
        p_limit: opts.limit ?? 500,
        p_offset: opts.offset ?? 0,
      }),
    );
    return (out ?? []) as Json[];
  }

  /// A doctor who has left, for the visits they saw: on the roster but
  /// inactive, so nobody books them. Admins. Returns the roster id.
  async addFormerDoctor(clinicId: string, name: string): Promise<string> {
    const row = await must(
      this.db
        .from('doctors')
        .insert({ clinic_id: clinicId, full_name: name, specialty: '', available_time_slots: [], is_active: false })
        .select('id')
        .single(),
    );
    return (row as Json).id;
  }

  // ── Roster, catalogue and time off (admins; a doctor their own schedule) ──

  /// Adds a doctor to [clinicId]'s roster.
  addDoctor(args: {
    clinicId: string;
    name: string;
    specialty: string;
    weekdays: number[];
    timeSlots: string[];
  }): Promise<void> {
    return run(
      this.db.from('doctors').insert({
        clinic_id: args.clinicId,
        full_name: args.name,
        specialty: args.specialty,
        available_weekdays: args.weekdays,
        available_time_slots: args.timeSlots,
      }),
    );
  }

  /// Changes a roster row. The database lets a doctor change only their own
  /// weekdays and time slots; everything else is the admin's.
  updateDoctor(doctorId: string, changes: Json): Promise<void> {
    return run(this.db.from('doctors').update(changes).eq('id', doctorId));
  }

  addService(args: { clinicId: string; name: string; durationMinutes: number; price?: number | null }): Promise<void> {
    return run(
      this.db.from('services').insert({
        clinic_id: args.clinicId,
        name: args.name,
        duration_minutes: args.durationMinutes,
        price: args.price ?? null,
      }),
    );
  }

  /// Services are retired (`is_active: false`), never deleted: past visits
  /// point at them.
  updateService(serviceId: string, changes: Json): Promise<void> {
    return run(this.db.from('services').update(changes).eq('id', serviceId));
  }

  /// Books leave for [doctorId], or closes the whole clinic when it is null.
  addTimeOff(args: {
    clinicId: string;
    doctorId?: string | null;
    startsOn: Date;
    endsOn: Date;
    reason?: string | null;
  }): Promise<void> {
    return run(
      this.db.from('doctor_time_off').insert({
        clinic_id: args.clinicId,
        doctor_id: args.doctorId ?? null,
        starts_on: formatDay(args.startsOn),
        ends_on: formatDay(args.endsOn),
        reason: trimOrNull(args.reason),
      }),
    );
  }

  deleteTimeOff(id: string): Promise<void> {
    return run(this.db.from('doctor_time_off').delete().eq('id', id));
  }

  async updateMyProfile(changes: { fullName?: string; phone?: string }): Promise<void> {
    const uid = await this.uid();
    if (uid == null) return;
    await run(
      this.db
        .from('profiles')
        .update({
          ...(changes.fullName != null ? { full_name: changes.fullName } : {}),
          ...(changes.phone != null ? { phone: changes.phone } : {}),
        })
        .eq('id', uid),
    );
  }

  // ── Billing ───────────────────────────────────────────────────────────────
  // The database computes every total and moves every status; see
  // 20260924120100_billing. The front desk and admins write, other staff
  // read, a patient reads their own bills once issued.

  /// Bills at [clinicId], newest first.
  async fetchInvoices(clinicId: string): Promise<Invoice[]> {
    const rows = await must(
      this.db
        .from('invoices')
        .select(HealthRepository.invoiceSelect)
        .eq('clinic_id', clinicId)
        .order('created_at', { ascending: false })
        .limit(300),
    );
    return (rows as Json[]).map(Invoice.fromJson);
  }

  /// Bills on one chart, newest first. For a patient, RLS already leaves out
  /// drafts.
  async fetchPatientInvoices(patientId: string): Promise<Invoice[]> {
    const rows = await must(
      this.db
        .from('invoices')
        .select(HealthRepository.invoiceSelect)
        .eq('patient_id', patientId)
        .order('created_at', { ascending: false }),
    );
    return (rows as Json[]).map(Invoice.fromJson);
  }

  async fetchInvoice(invoiceId: string): Promise<Invoice | null> {
    const row = await must(
      this.db.from('invoices').select(HealthRepository.invoiceSelect).eq('id', invoiceId).maybeSingle(),
    );
    return row == null ? null : Invoice.fromJson(row);
  }

  /// The visit's live bill — not a voided one — or null.
  async fetchAppointmentInvoice(appointmentId: string): Promise<Invoice | null> {
    const row = await must(
      this.db
        .from('invoices')
        .select(HealthRepository.invoiceSelect)
        .eq('appointment_id', appointmentId)
        .neq('status', 'void')
        .maybeSingle(),
    );
    return row == null ? null : Invoice.fromJson(row);
  }

  /// A draft for the visit with its service as the first line, or its
  /// existing bill. Returns the bill's id.
  async createInvoiceForAppointment(appointmentId: string): Promise<string> {
    return (await must(this.db.rpc('create_invoice_for_appointment', { p_appointment_id: appointmentId }))) as string;
  }

  /// An empty draft for a chart, not tied to a visit.
  async createInvoice(args: { clinicId: string; patientId: string }): Promise<string> {
    const row = await must(
      this.db.from('invoices').insert({ clinic_id: args.clinicId, patient_id: args.patientId }).select('id').single(),
    );
    return (row as Json).id;
  }

  addInvoiceItem(args: {
    invoiceId: string;
    clinicId: string;
    description: string;
    unitPrice: number;
    quantity?: number;
    serviceId?: string | null;
  }): Promise<void> {
    return run(
      this.db.from('invoice_items').insert({
        invoice_id: args.invoiceId,
        clinic_id: args.clinicId,
        description: args.description.trim(),
        unit_price: args.unitPrice,
        quantity: args.quantity ?? 1,
        service_id: args.serviceId ?? null,
      }),
    );
  }

  updateInvoiceItem(itemId: string, args: { description: string; unitPrice: number; quantity: number }): Promise<void> {
    return run(
      this.db
        .from('invoice_items')
        .update({ description: args.description.trim(), unit_price: args.unitPrice, quantity: args.quantity })
        .eq('id', itemId),
    );
  }

  deleteInvoiceItem(itemId: string): Promise<void> {
    return run(this.db.from('invoice_items').delete().eq('id', itemId));
  }

  /// The discount on a draft. Zero clears it.
  setInvoiceDiscount(invoiceId: string, args: { amount: number; reason?: string | null }): Promise<void> {
    return run(
      this.db
        .from('invoices')
        .update({
          discount_amount: args.amount,
          discount_reason: args.amount === 0 ? null : trimOrNull(args.reason),
        })
        .eq('id', invoiceId),
    );
  }

  setInvoiceNotes(invoiceId: string, notes: string | null): Promise<void> {
    return run(this.db.from('invoices').update({ notes: trimOrNull(notes) }).eq('id', invoiceId));
  }

  /// Numbers and locks the bill; returns its number.
  async issueInvoice(invoiceId: string): Promise<string> {
    return (await must(this.db.rpc('issue_invoice', { p_invoice_id: invoiceId }))) as string;
  }

  voidInvoice(invoiceId: string, reason: string): Promise<void> {
    return run(this.db.rpc('void_invoice', { p_invoice_id: invoiceId, p_reason: reason }));
  }

  /// Drafts only; the database refuses the rest.
  deleteInvoice(invoiceId: string): Promise<void> {
    return run(this.db.from('invoices').delete().eq('id', invoiceId));
  }

  recordPayment(args: {
    invoiceId: string;
    clinicId: string;
    amount: number;
    method: PaymentMethod;
    reference?: string | null;
  }): Promise<void> {
    return run(
      this.db.from('payments').insert({
        invoice_id: args.invoiceId,
        clinic_id: args.clinicId,
        amount: args.amount,
        method: args.method,
        reference: trimOrNull(args.reference),
      }),
    );
  }

  /// Admins only.
  voidPayment(paymentId: string, reason: string): Promise<void> {
    return run(this.db.rpc('void_payment', { p_payment_id: paymentId, p_reason: reason }));
  }

  async fetchBillingSummary(clinicId: string, range: { from: Date; to: Date }): Promise<BillingSummary> {
    const row = await must(
      this.db.rpc('billing_summary', {
        p_clinic_id: clinicId,
        p_from: formatDay(range.from),
        p_to: formatDay(range.to),
      }),
    );
    return BillingSummary.fromJson(row as Json);
  }

  // ── Prices, expenses and the ledger ───────────────────────────────────────
  // 20260930120000_payments_ledger. The front desk and admins.

  /// Null clears the price.
  setServicePrice(serviceId: string, price: number | null): Promise<void> {
    return run(this.db.rpc('set_service_price', { p_service_id: serviceId, p_price: price }));
  }

  async fetchLedgerSummary(clinicId: string, range: { from: Date; to: Date }): Promise<LedgerSummary> {
    const row = await must(
      this.db.rpc('ledger_summary', {
        p_clinic_id: clinicId,
        p_from: formatDay(range.from),
        p_to: formatDay(range.to),
      }),
    );
    return LedgerSummary.fromJson(row as Json);
  }

  /// Payments and expenses in the range, newest first.
  async fetchLedgerEntries(clinicId: string, range: { from: Date; to: Date }): Promise<LedgerEntry[]> {
    const rows = await must(
      this.db.rpc('ledger_entries', {
        p_clinic_id: clinicId,
        p_from: formatDay(range.from),
        p_to: formatDay(range.to),
      }),
    );
    return ((rows ?? []) as Json[]).map(LedgerEntry.fromJson);
  }

  addExpense(args: {
    clinicId: string;
    spentOn: Date;
    category: string;
    amount: number;
    method: PaymentMethod;
    description?: string | null;
    reference?: string | null;
  }): Promise<void> {
    return run(
      this.db.from('expenses').insert({
        clinic_id: args.clinicId,
        spent_on: formatDay(args.spentOn),
        category: args.category,
        amount: args.amount,
        method: args.method,
        description: args.description ?? null,
        reference: args.reference ?? null,
      }),
    );
  }

  /// Admins only.
  voidExpense(expenseId: string, reason: string): Promise<void> {
    return run(this.db.rpc('void_expense', { p_expense_id: expenseId, p_reason: reason }));
  }

  // ── Notifications ─────────────────────────────────────────────────────────

  /// The newest 100 entries in the signed-in account's inbox for [app],
  /// newest first. RLS sends each account only its own rows.
  async fetchNotifications(app: AppRole): Promise<AppNotification[]> {
    const uid = await this.uid();
    if (uid == null) return [];
    const rows = await must(
      this.db
        .from('notifications')
        .select()
        .eq('profile_id', uid)
        .eq('app', app)
        .order('created_at', { ascending: false })
        .limit(100),
    );
    return (rows as Json[]).map(AppNotification.fromJson);
  }

  /// Calls [onChange] whenever a row of the signed-in account's inbox is
  /// added, read or removed, over Realtime. Returns the unsubscribe.
  watchNotifications(uid: string, onChange: () => void): () => void {
    const channel = this.db
      .channel(`notifications:${uid}:${Math.random().toString(36).slice(2)}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'notifications', filter: `profile_id=eq.${uid}` }, () =>
        onChange(),
      )
      .subscribe();
    return () => {
      void this.db.removeChannel(channel);
    };
  }

  /// Marks [ids] read; with none given, everything unread in [app].
  markNotificationsRead(app: AppRole, ids?: string[]): Promise<void> {
    let q = this.db
      .from('notifications')
      .update({ read_at: new Date().toISOString() })
      .eq('app', app)
      .is('read_at', null);
    if (ids != null) q = q.in('id', ids);
    return run(q);
  }

  /// Registers this browser for [app]'s pushes to the signed-in account.
  savePushSubscription(args: {
    app: AppRole;
    endpoint: string;
    p256dh: string;
    auth: string;
    userAgent?: string | null;
  }): Promise<void> {
    return run(
      this.db.rpc('save_push_subscription', {
        p_app: args.app,
        p_endpoint: args.endpoint,
        p_p256dh: args.p256dh,
        p_auth: args.auth,
        p_user_agent: args.userAgent ?? null,
      }),
    );
  }

  deletePushSubscription(endpoint: string): Promise<void> {
    return run(this.db.rpc('delete_push_subscription', { p_endpoint: endpoint }));
  }

  /// The notification kinds the signed-in account switched off in [app]. The
  /// database skips writing those (see 20260928120000 in the backend).
  async fetchNotificationMutes(app: AppRole): Promise<Set<string>> {
    const uid = await this.uid();
    if (uid == null) return new Set();
    const rows = await must(
      this.db.from('notification_mutes').select('kind').eq('profile_id', uid).eq('app', app),
    );
    return new Set((rows as Json[]).map((r) => r.kind as string));
  }

  /// Switches [kind] on or off for the signed-in account in [app].
  async setNotificationMuted(app: AppRole, kind: string, muted: boolean): Promise<void> {
    const uid = await this.uid();
    if (uid == null) throw new Error('Sign in first.');
    const table = this.db.from('notification_mutes');
    if (muted) {
      await run(table.upsert({ profile_id: uid, app, kind }, { ignoreDuplicates: true }));
      return;
    }
    await run(table.delete().eq('profile_id', uid).eq('app', app).eq('kind', kind));
  }

  // ── Onboarding ────────────────────────────────────────────────────────────

  /// Attaches the signed-in account to the clinic with this code, creating
  /// their chart there. Returns the clinic id. Safe to repeat.
  async joinClinic(code: string): Promise<string> {
    return (await must(this.db.rpc('join_clinic', { p_join_code: code }))) as string;
  }

  /// Grants [role] at [clinicId] to the account registered under [email].
  /// Admin-only; the account must already exist. [branchLocked] makes an
  /// admin a branch admin, and only a full admin may grant either kind.
  inviteStaff(args: { clinicId: string; email: string; role: AppRole; branchLocked?: boolean }): Promise<void> {
    return run(
      this.db.rpc('invite_staff', {
        p_clinic_id: args.clinicId,
        p_email: args.email,
        p_role: args.role,
        p_branch_locked: args.branchLocked ?? false,
      }),
    );
  }

  removeStaff(args: { clinicId: string; profileId: string }): Promise<void> {
    return run(this.db.rpc('remove_staff', { p_clinic_id: args.clinicId, p_profile_id: args.profileId }));
  }

  /// Updates the clinic's own presentation and contact details. The database
  /// only lets an admin write those columns — name, logo, colour, contact,
  /// timezone, join code — and not the clinic's type, slug or active status.
  updateClinic(clinicId: string, changes: Json): Promise<void> {
    return run(this.db.from('clinics').update(changes).eq('id', clinicId));
  }

  /// Issues a fresh join code, invalidating the old one. Returns the new code.
  async rotateJoinCode(clinicId: string): Promise<string> {
    return (await must(this.db.rpc('rotate_join_code', { p_clinic_id: clinicId }))) as string;
  }

  // ── Staff codes ───────────────────────────────────────────────────────────

  /// Every staff code issued at [clinicId] and what became of it, newest
  /// first. Readable by the clinic's admins, branch admins included.
  async fetchStaffInvites(clinicId: string): Promise<StaffInvite[]> {
    const rows = await must(
      this.db.from('staff_invites').select().eq('clinic_id', clinicId).order('created_at', { ascending: false }),
    );
    return (rows as Json[]).map(StaffInvite.fromJson);
  }

  /// Issues a single-use code for one doctor or assistant.
  async createStaffInvite(args: { clinicId: string; role: AppRole; label?: string | null }): Promise<StaffInvite> {
    const row = await must(
      this.db.rpc('create_staff_invite', { p_clinic_id: args.clinicId, p_role: args.role, p_label: args.label ?? null }),
    );
    return StaffInvite.fromJson(row as Json);
  }

  revokeStaffInvite(inviteId: string): Promise<void> {
    return run(this.db.rpc('revoke_staff_invite', { p_invite_id: inviteId }));
  }

  /// Approves or rejects a request. Approving a doctor needs either an
  /// unlinked roster entry at the clinic ([doctorId]) or a [specialty] to
  /// create one with.
  decideStaffRequest(args: {
    inviteId: string;
    approve: boolean;
    doctorId?: string | null;
    specialty?: string | null;
  }): Promise<void> {
    return run(
      this.db.rpc('decide_staff_request', {
        p_invite_id: args.inviteId,
        p_approve: args.approve,
        p_doctor_id: args.doctorId ?? null,
        p_specialty: args.specialty ?? null,
      }),
    );
  }

  /// Files a request to join a clinic as [app] — the app the code was typed
  /// into. Grants nothing until an admin approves.
  redeemStaffInvite(code: string, app: AppRole): Promise<void> {
    return run(this.db.rpc('redeem_staff_invite', { p_code: code, p_app_role: app }));
  }

  /// The signed-in account's own requests, newest first.
  async fetchMyStaffRequests(): Promise<StaffRequest[]> {
    if ((await this.uid()) == null) return [];
    const rows = await must(this.db.rpc('my_staff_requests'));
    return ((rows ?? []) as Json[]).map(StaffRequest.fromJson);
  }

  // ── Auth ──────────────────────────────────────────────────────────────────

  // [captchaToken] on sign-in, sign-up and the reset code: Supabase Auth
  // requires one from Cloudflare Turnstile once CAPTCHA protection is on, and
  // ignores it while it is off. See useHumanCheck.

  async signIn(email: string, password: string, captchaToken?: string | null): Promise<void> {
    await auth(
      this.db.auth.signInWithPassword({ email, password, options: { captchaToken: captchaToken ?? undefined } }),
    );
  }

  /// Leaves for Google's sign-in page; Google sends the browser back to
  /// [redirectTo], where Supabase finishes signing in as the page loads (see
  /// createPlatform). The first time, this also creates the account — with
  /// the name Google gives, which handle_new_user reads as `full_name`.
  ///
  /// Web only. [redirectTo] must match Supabase Auth's redirect allow list,
  /// or Supabase sends the browser to its Site URL instead.
  async signInWithGoogle(redirectTo: string): Promise<void> {
    await auth(
      this.db.auth.signInWithOAuth({
        provider: 'google',
        options: { redirectTo, queryParams: { prompt: 'select_account' } },
      }),
    );
  }

  /// Whether Supabase Auth has Google switched on, from its public
  /// settings. False when it cannot tell: the button would only lead to an
  /// error page.
  async googleSignInEnabled(): Promise<boolean> {
    try {
      const res = await fetch(`${SupabaseConfig.url}/auth/v1/settings`, {
        headers: { apikey: SupabaseConfig.publishableKey },
      });
      if (!res.ok) return false;
      const body = (await res.json()) as { external?: { google?: boolean } };
      return body.external?.google === true;
    } catch {
      return false;
    }
  }

  /// The policy versions the signed-in account has acknowledged, as
  /// `privacy@2026-09-30` / `terms@2026-09-30`.
  async fetchMyPolicyAcknowledgements(): Promise<Set<string>> {
    const rows = await must(this.db.from('policy_acknowledgements').select('document, version'));
    return new Set(((rows ?? []) as Json[]).map((r) => `${r.document}@${r.version}`));
  }

  /// Records that the signed-in account was shown [version] of [document]
  /// and agreed. Acknowledging the same version twice keeps the first time.
  acknowledgePolicy(document: 'privacy' | 'terms', version: string): Promise<void> {
    return run(this.db.rpc('acknowledge_policy', { p_document: document, p_version: version }));
  }

  /// Emails a one-time recovery code. Supabase answers the same whether or
  /// not the address has an account, so this reveals nothing about who
  /// signed up.
  ///
  /// The email must show `{{ .Token }}`: the default template only has a
  /// link, and this app asks for the code instead (see the backend README).
  async sendPasswordResetCode(email: string, captchaToken?: string | null): Promise<void> {
    await auth(this.db.auth.resetPasswordForEmail(email.trim(), { captchaToken: captchaToken ?? undefined }));
  }

  /// Exchanges the emailed code for a session, then sets the new password.
  ///
  /// Verifying signs the user in. That is why these are two steps the caller
  /// can drive separately: if the password update fails after a good code, a
  /// retry must not spend the code a second time.
  async verifyPasswordResetCode(email: string, code: string): Promise<void> {
    await auth(this.db.auth.verifyOtp({ email: email.trim(), token: code.trim(), type: 'recovery' }));
  }

  /// Sets a new password for the signed-in account.
  async changePassword(newPassword: string): Promise<void> {
    await auth(this.db.auth.updateUser({ password: newPassword }));
  }

  /// Creates an account and nothing else. Access is granted separately: a
  /// patient joins a clinic with its code, staff are added by a clinic admin.
  /// [privacyPolicyVersion] and [termsVersion] are what the person agreed to;
  /// the database records them against the new account (RA 10173).
  async signUp(
    email: string,
    password: string,
    fullName: string,
    opts: { captchaToken?: string | null; privacyPolicyVersion?: string; termsVersion?: string } = {},
  ): Promise<void> {
    await auth(
      this.db.auth.signUp({
        email,
        password,
        options: {
          data: {
            full_name: fullName,
            ...(opts.privacyPolicyVersion != null ? { privacy_policy_version: opts.privacyPolicyVersion } : {}),
            ...(opts.termsVersion != null ? { terms_version: opts.termsVersion } : {}),
          },
          captchaToken: opts.captchaToken ?? undefined,
        },
      }),
    );
  }

  /// Signs out — after unhooking this browser's push notifications, so the
  /// next person to use it does not receive this account's. That step never
  /// holds up signing out.
  async signOut(): Promise<void> {
    if (this.beforeSignOut) {
      try {
        await Promise.race([
          this.beforeSignOut(),
          new Promise((_, reject) => setTimeout(() => reject(new Error('timeout')), 3000)),
        ]);
      } catch {
        // Never holds up signing out.
      }
    }
    await auth(this.db.auth.signOut());
  }
}
