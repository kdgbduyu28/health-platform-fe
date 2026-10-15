import type { IconName } from '../theme/icons';

/// Mirrors `public.appointment_status`. The flow, which the database enforces
/// (see 20260923120100 in health-platform-be):
///
///   pending → confirmed → arrived → in_consultation → completed
///                 └───────────────────────┘ (a doctor may start from confirmed)
///
/// plus `cancelled` before the consultation and `no_show` once a confirmed
/// visit's time has passed.
export type AppointmentStatus =
  | 'pending'
  | 'confirmed'
  | 'arrived'
  | 'in_consultation'
  | 'completed'
  | 'cancelled'
  | 'no_show';

export const appointmentStatuses: readonly AppointmentStatus[] = [
  'pending',
  'confirmed',
  'arrived',
  'in_consultation',
  'completed',
  'cancelled',
  'no_show',
];

export function appointmentStatusFromWire(value: string): AppointmentStatus {
  if ((appointmentStatuses as readonly string[]).includes(value)) return value as AppointmentStatus;
  throw new Error(`unknown appointment status: ${value}`);
}

/// Still on the doctor's calendar: it blocks the time and counts as a visit
/// to come or in progress. Cancelled visits and no-shows free it.
export function holdsTime(s: AppointmentStatus): boolean {
  return s !== 'cancelled' && s !== 'no_show';
}

/// Not yet finished one way or another.
export function isOpenStatus(s: AppointmentStatus): boolean {
  return s === 'pending' || s === 'confirmed' || s === 'arrived' || s === 'in_consultation';
}

/// What a patient may still cancel from the app. Later than this they call
/// the clinic; the database refuses it too.
export function patientCanCancel(s: AppointmentStatus): boolean {
  return s === 'pending' || s === 'confirmed';
}

/// What the front desk may still cancel.
export function staffCanCancel(s: AppointmentStatus): boolean {
  return s === 'pending' || s === 'confirmed' || s === 'arrived';
}

/// In the building: checked in, or with the doctor.
export function isOnSite(s: AppointmentStatus): boolean {
  return s === 'arrived' || s === 'in_consultation';
}

export const statusMeta: Record<AppointmentStatus, { label: string; color: string; icon: IconName }> = {
  pending: { label: 'Pending', color: '#FF9800', icon: 'schedule' },
  confirmed: { label: 'Confirmed', color: '#4CAF50', icon: 'check-circle-outline' },
  arrived: { label: 'Waiting', color: '#9C27B0', icon: 'chair' },
  in_consultation: { label: 'With doctor', color: '#00897B', icon: 'medical-services' },
  completed: { label: 'Completed', color: '#2196F3', icon: 'task-alt' },
  cancelled: { label: 'Cancelled', color: '#F44336', icon: 'cancel' },
  no_show: { label: 'No-show', color: '#757575', icon: 'person-off' },
};
