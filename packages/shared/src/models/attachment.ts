import type { IconName } from '../theme/icons';
import { parseDayOrNull, parseTime } from '../util/dates';

type Json = Record<string, any>;

export type AttachmentKind = 'xray' | 'photo' | 'document';
export const attachmentKinds: readonly AttachmentKind[] = ['xray', 'photo', 'document'];
export const attachmentKindMeta: Record<AttachmentKind, { label: string; icon: IconName }> = {
  xray: { label: 'X-ray', icon: 'medical-information' },
  photo: { label: 'Photo', icon: 'image' },
  document: { label: 'Document', icon: 'file-open' },
};

/// What the bucket takes — see 20261106120100_chart_attachments.
export const attachmentMimeTypes = ['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'application/pdf'] as const;
export const maxAttachmentBytes = 15 * 1024 * 1024;
/// Supabase's free tier: 1 GB of Storage for the whole platform, every
/// clinic together.
export const freeTierStorageBytes = 1024 * 1024 * 1024;

/// Why a picked file cannot be uploaded, or null when it can.
export function attachmentProblem(file: { type: string; size: number }): string | null {
  if (!(attachmentMimeTypes as readonly string[]).includes(file.type)) return 'Only JPEG, PNG, WebP, HEIC and PDF files.';
  if (file.size > maxAttachmentBytes) return 'The file is over 15 MB.';
  if (file.size === 0) return 'The file is empty.';
  return null;
}

/// `1.2 MB`, `340 KB`.
export function formatBytes(n: number): string {
  if (n >= 1024 * 1024) return `${(n / (1024 * 1024)).toFixed(1)} MB`;
  return `${Math.max(1, Math.round(n / 1024))} KB`;
}

/// One file on a chart, from `public.chart_attachments`. The file itself is
/// in Storage at [storagePath]; read it through a short-lived signed URL.
export class ChartAttachment {
  constructor(
    readonly id: string,
    readonly clinicId: string,
    readonly patientId: string,
    readonly appointmentId: string | null,
    readonly kind: AttachmentKind,
    readonly storagePath: string,
    readonly fileName: string,
    readonly mimeType: string,
    readonly sizeBytes: number,
    readonly caption: string | null,
    readonly takenOn: Date | null,
    readonly sharedWithPatient: boolean,
    readonly createdAt: Date,
  ) {}

  get isImage(): boolean {
    return this.mimeType.startsWith('image/') && this.mimeType !== 'image/heic';
  }

  /// When it was taken, or else uploaded.
  get date(): Date {
    return this.takenOn ?? this.createdAt;
  }

  static fromJson(json: Json): ChartAttachment {
    const kind = attachmentKinds.includes(json.kind) ? (json.kind as AttachmentKind) : 'document';
    return new ChartAttachment(
      json.id,
      json.clinic_id,
      json.patient_id,
      json.appointment_id ?? null,
      kind,
      json.storage_path,
      json.file_name,
      json.mime_type,
      Number(json.size_bytes ?? 0),
      json.caption ?? null,
      parseDayOrNull(json.taken_on),
      json.shared_with_patient === true,
      parseTime(json.created_at),
    );
  }
}
