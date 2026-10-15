import type { IconName } from '../theme/icons';
import { parseTime, parseTimeOrNull } from '../util/dates';
import { type AppRole, appRoleFromWire } from './app_role';

type Json = Record<string, any>;

/// One entry in an account's inbox, from `public.notifications`.
///
/// The database writes these as visits and bills move (see
/// 20260924120200_notifications in health-platform-be) and pushes them to
/// subscribed browsers. Each belongs to one app: a doctor who is also a
/// patient somewhere sees each in the right place.
export class AppNotification {
  constructor(
    readonly id: string,
    readonly app: AppRole,
    readonly kind: string,
    readonly title: string,
    readonly body: string,
    readonly createdAt: Date,
    readonly clinicId: string | null = null,
    /// A path in this app, clinic slug included: `/dtouchdental/appointments/…`.
    readonly link: string | null = null,
    readonly appointmentId: string | null = null,
    readonly readAt: Date | null = null,
  ) {}

  get isRead(): boolean {
    return this.readAt != null;
  }

  get icon(): IconName {
    switch (this.kind) {
      case 'booking_requested':
        return 'event-note';
      case 'visit_confirmed':
        return 'check-circle-outline';
      case 'visit_moved':
        return 'update';
      case 'visit_cancelled':
        return 'event-busy';
      case 'visit_reminder':
        return 'alarm';
      case 'patient_arrived':
        return 'chair';
      case 'patient_note':
        return 'chat-bubble-outline';
      case 'invoice_issued':
        return 'receipt-long';
      default:
        return 'notifications-none';
    }
  }

  static fromJson(json: Json): AppNotification {
    return new AppNotification(
      json.id,
      appRoleFromWire(json.app),
      json.kind,
      json.title,
      json.body,
      parseTime(json.created_at),
      json.clinic_id ?? null,
      json.link ?? null,
      json.appointment_id ?? null,
      parseTimeOrNull(json.read_at),
    );
  }
}

/// A kind of notification someone can switch off in Settings. The kinds are
/// the database's (`notification_mutes.kind`); the words are ours.
export type NotificationTopic = { kind: string; label: string; description: string };

/// What [app] can be told about, in the order Settings lists them. Mirrors
/// who hears what in 20260924120200_notifications.
export function notificationTopicsFor(app: AppRole): NotificationTopic[] {
  const t = (kind: string, label: string, description: string) => ({ kind, label, description });
  switch (app) {
    case 'patient':
      return [
        t('visit_reminder', 'Visit reminders', 'The day before a confirmed visit'),
        t('visit_confirmed', 'Visit confirmed', 'When the clinic confirms a booking'),
        t('visit_moved', 'Visit moved', 'When the clinic changes the time'),
        t('visit_cancelled', 'Visit cancelled', 'When the clinic cancels a visit'),
        t('patient_note', 'Notes from your doctor', 'Advice written after a visit'),
        t('invoice_issued', 'Bills', 'When a new bill is ready'),
      ];
    case 'assistant':
    case 'admin':
      return [
        t('booking_requested', 'Booking requests', 'A patient asks for a visit'),
        t('visit_moved', 'Reschedule requests', 'A patient asks to move a visit'),
        t('visit_cancelled', 'Cancellations', 'A patient cancels a visit'),
      ];
    case 'doctor':
      return [t('patient_arrived', 'Patient arrived', 'Your patient is checked in and waiting')];
  }
}
