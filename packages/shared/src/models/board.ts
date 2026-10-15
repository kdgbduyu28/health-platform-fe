import type { AppRole } from './app_role';
import type { Appointment } from './appointment';
import type { AppointmentStatus } from './appointment_status';
import type { IconName } from '../theme/icons';

/// The columns of AppointmentBoard, left to right as a visit moves through
/// the day. Cancelled visits and no-shows are in none of them: they sit
/// folded away under Completed.
export type BoardColumn = 'upcoming' | 'planned' | 'in_progress' | 'completed';
export const boardColumns: readonly BoardColumn[] = ['upcoming', 'planned', 'in_progress', 'completed'];
export const columnMeta: Record<BoardColumn, { label: string; tone: AppointmentStatus }> = {
  upcoming: { label: 'Upcoming', tone: 'pending' },
  planned: { label: 'Planned', tone: 'confirmed' },
  in_progress: { label: 'In progress', tone: 'in_consultation' },
  completed: { label: 'Completed', tone: 'completed' },
};

export function boardColumnOf(s: AppointmentStatus): BoardColumn | null {
  switch (s) {
    case 'pending':
      return 'upcoming';
    case 'confirmed':
      return 'planned';
    case 'arrived':
    case 'in_consultation':
      return 'in_progress';
    case 'completed':
      return 'completed';
    default:
      return null;
  }
}

/// The one move forward a visit can make from where it stands, for whoever
/// is looking — the board's button, and what dragging a card does.
export type BoardStep = { to: AppointmentStatus; label: string; icon: IconName; done: string };

/// What [app] can do next with [a]. [clinician] is whether the signed-in
/// membership may start consultations (doctors and admins).
///
/// Mirrors the flow the database enforces (20260930120000): the front desk
/// confirms, checks in and marks a visit done; only clinicians start a
/// consultation. Marking done opens the complete-visit sheet. From
/// "Planned", the doctor app starts the consultation itself — a doctor
/// dragging a card into "In progress" is seeing that patient — while the
/// desk and admin apps check the patient in to the waiting room.
export function boardNextStep(a: Appointment, app: AppRole, clinician: boolean): BoardStep | null {
  const who = a.patient.name;
  switch (a.status) {
    case 'pending':
      return { to: 'confirmed', label: 'Confirm', icon: 'check', done: 'Appointment confirmed' };
    case 'confirmed':
      return app === 'doctor'
        ? { to: 'in_consultation', label: 'Start', icon: 'play-arrow', done: `Consultation with ${who} started` }
        : { to: 'arrived', label: 'Check in', icon: 'how-to-reg', done: `${who} is in the waiting room` };
    case 'arrived':
      if (clinician) return { to: 'in_consultation', label: 'Start', icon: 'play-arrow', done: `Consultation with ${who} started` };
      return { to: 'completed', label: 'Mark done', icon: 'task-alt', done: 'Visit done' };
    case 'in_consultation':
      return { to: 'completed', label: 'Mark done', icon: 'task-alt', done: 'Visit done' };
    default:
      return null;
  }
}
