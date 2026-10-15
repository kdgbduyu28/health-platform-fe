import { addMinutes, isSameDay, parseTime, parseTimeOrNull } from '../util/dates';
import { type AppointmentStatus, appointmentStatusFromWire } from './appointment_status';
import { ClinicalNote } from './clinical_note';
import { Doctor } from './doctor';
import { Patient } from './patient';

type Json = Record<string, any>;

export class Appointment {
  constructor(
    readonly id: string,
    readonly clinicId: string,
    /// The chart at [clinicId]. The database refuses an appointment whose
    /// chart belongs to any other clinic.
    readonly patient: Patient,
    readonly doctor: Doctor,
    readonly dateTime: Date,
    readonly service: string,
    readonly status: AppointmentStatus,
    /// What the doctor wants the patient to read. Visible to anyone who can
    /// see the appointment; only the clinic's doctors and admins can write it.
    readonly patientNote: string | null = null,
    /// The consultation note — present only when the appointment was fetched
    /// with it embedded (a clinician's view of a patient's history). Null
    /// otherwise, which does not mean no note was written.
    readonly visitNote: ClinicalNote | null = null,
    readonly serviceId: string | null = null,
    /// From the service, set by the database. The visit runs until [endsAt].
    readonly durationMinutes: number = 30,
    /// When the front desk checked the patient in, the doctor started, and
    /// the doctor finished. Stamped by the database as the status moves.
    readonly arrivedAt: Date | null = null,
    readonly startedAt: Date | null = null,
    readonly completedAt: Date | null = null,
    /// Where the visit was before it was last moved, and how often it has
    /// been.
    readonly rescheduledFrom: Date | null = null,
    readonly rescheduleCount: number = 0,
  ) {}

  get endsAt(): Date {
    return addMinutes(this.dateTime, this.durationMinutes);
  }

  /// Expects the chart (with its person) and the doctor embedded:
  ///
  ///   appointments?select=*,patient:patients(*,person:persons(*)),
  ///                        doctor:doctors(*)
  ///
  /// optionally with `visit_note:visit_notes(*)` as well.
  static fromJson(json: Json): Appointment {
    return new Appointment(
      json.id,
      json.clinic_id,
      Patient.fromJson(json.patient),
      Doctor.fromJson(json.doctor),
      parseTime(json.scheduled_at),
      json.service_name,
      appointmentStatusFromWire(json.status),
      blankToNull(json.patient_note),
      ClinicalNote.fromNullableJson(json.visit_note),
      json.service_id ?? null,
      json.duration_minutes ?? 30,
      parseTimeOrNull(json.arrived_at),
      parseTimeOrNull(json.started_at),
      parseTimeOrNull(json.completed_at),
      parseTimeOrNull(json.rescheduled_from),
      json.reschedule_count ?? 0,
    );
  }

  copyWith(changes: { status?: AppointmentStatus; patientNote?: string | null }): Appointment {
    return new Appointment(
      this.id,
      this.clinicId,
      this.patient,
      this.doctor,
      this.dateTime,
      this.service,
      changes.status ?? this.status,
      changes.patientNote ?? this.patientNote,
      this.visitNote,
      this.serviceId,
      this.durationMinutes,
      this.arrivedAt,
      this.startedAt,
      this.completedAt,
      this.rescheduledFrom,
      this.rescheduleCount,
    );
  }

  /// Can still be moved: it has not started. The database refuses the rest.
  get canReschedule(): boolean {
    return this.status === 'pending' || this.status === 'confirmed';
  }

  get isUpcoming(): boolean {
    return this.dateTime.getTime() > Date.now();
  }

  get isToday(): boolean {
    return isSameDay(this.dateTime, new Date());
  }
}

function blankToNull(s: string | null | undefined): string | null {
  return s == null || s.trim() === '' ? null : s;
}
