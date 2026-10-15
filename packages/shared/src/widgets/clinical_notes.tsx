import { useQueryClient } from '@tanstack/react-query';
import { format } from 'date-fns';
import { useState } from 'react';
import { View } from 'react-native';
import { ActivityIndicator, Button, ProgressBar, Text } from 'react-native-paper';

import type { Appointment } from '../models/appointment';
import type { Patient } from '../models/patient';
import { useAppointmentActions } from '../queries/appointments';
import { type AsyncValue, asyncData, mapAsync } from '../queries/async_value';
import { useCanSeeClinicalNotes, useChartNote, useVisitNote } from '../queries/clinical';
import { useRepository } from '../state/platform';
import { useAppTheme } from '../theme/clinic_theme';
import { describeError } from '../ui/async_view';
import { TextField } from '../ui/fields';
import { Icon, type IconName } from '../ui/icon';

/// The chart's standing medical note. Clinicians only; renders nothing for
/// anyone else.
export function ChartNoteSection({ patient }: { patient: Patient }) {
  const allowed = useCanSeeClinicalNotes().value ?? false;
  const note = useChartNote(patient.id);
  const repo = useRepository();
  const qc = useQueryClient();
  if (!allowed) return null;
  return (
    <View style={{ marginBottom: 12 }}>
      <NoteCard
        title="Medical notes"
        icon="medical-information"
        caption="Allergies and conditions every visit should know about. Doctors and admins only."
        hint="e.g. Allergic to latex"
        emptyText="Nothing on file."
        value={mapAsync(note, (n) => n?.body ?? null)}
        updatedAt={note.value?.updatedAt ?? null}
        onRetry={() => void qc.invalidateQueries({ queryKey: ['chartNote'] })}
        onSave={async (body) => {
          await repo.saveChartNote({ patientId: patient.id, clinicId: patient.clinicId, body });
          await qc.invalidateQueries({ queryKey: ['chartNote'] });
        }}
      />
    </View>
  );
}

/// The consultation note on one appointment. Clinicians only.
export function VisitNoteSection({ appointment }: { appointment: Appointment }) {
  const allowed = useCanSeeClinicalNotes().value ?? false;
  const note = useVisitNote(appointment.id);
  const repo = useRepository();
  const qc = useQueryClient();
  if (!allowed) return null;
  return (
    <View style={{ marginBottom: 12 }}>
      <NoteCard
        title="Consultation notes"
        icon="assignment"
        caption="Doctors and admins only. The patient never sees these."
        hint="Findings, treatment, follow-up…"
        emptyText="No consultation notes yet."
        value={mapAsync(note, (n) => n?.body ?? null)}
        updatedAt={note.value?.updatedAt ?? null}
        onRetry={() => void qc.invalidateQueries({ queryKey: ['visitNote'] })}
        onSave={async (body) => {
          await repo.saveVisitNote({ appointmentId: appointment.id, clinicId: appointment.clinicId, body });
          await Promise.all([
            qc.invalidateQueries({ queryKey: ['visitNote'] }),
            qc.invalidateQueries({ queryKey: ['patientHistory'] }),
          ]);
        }}
      />
    </View>
  );
}

/// What the doctor wants the patient to read about this visit.
///
/// Clinicians can edit it. Other staff see it read-only when there is one —
/// it is not clinical, and the front desk may be asked about it.
export function PatientNoteSection({ appointment }: { appointment: Appointment }) {
  const canWrite = useCanSeeClinicalNotes().value ?? false;
  const actions = useAppointmentActions();
  const note = appointment.patientNote;
  if (!canWrite && note == null) return null;
  return (
    <View style={{ marginBottom: 12 }}>
      <NoteCard
        title="Note to patient"
        icon="chat-bubble-outline"
        caption="The patient sees this in their app."
        hint="Aftercare, instructions, what to bring next time…"
        emptyText="No note for the patient."
        value={asyncData(note)}
        onSave={canWrite ? (body) => actions.updatePatientNote(appointment.id, body) : undefined}
      />
    </View>
  );
}

/// A titled note with an Edit → Save flow, for a value that may still be
/// loading or may have failed.
export function NoteCard({
  title,
  icon,
  value,
  caption,
  hint,
  emptyText = 'No notes yet.',
  updatedAt,
  onSave,
  onRetry,
}: {
  title: string;
  icon: IconName;
  /// The note text. Null or blank means there is none.
  value: AsyncValue<string | null>;
  caption?: string;
  hint?: string;
  emptyText?: string;
  updatedAt?: Date | null;
  /// Receives the trimmed text; an empty string clears the note. Absent
  /// makes the card read-only.
  onSave?: (body: string) => Promise<void>;
  onRetry?: () => void;
}) {
  const { colors } = useAppTheme();
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const text = value.value?.trim() ?? '';
  const hasText = text !== '';

  const save = async () => {
    if (onSave == null || busy) return;
    setBusy(true);
    setError(null);
    try {
      await onSave(draft.trim());
      setEditing(false);
    } catch (e) {
      setError(describeError(e));
    } finally {
      setBusy(false);
    }
  };

  return (
    <View style={{ padding: 16, borderRadius: 16, backgroundColor: colors.surfaceContainerLow }}>
      <View style={{ flexDirection: 'row', alignItems: 'center', gap: 6 }}>
        <Icon name={icon} size={16} color={colors.onSurfaceVariant} />
        <Text style={{ flex: 1, fontWeight: '600', color: colors.onSurfaceVariant, fontSize: 12 }}>{title}</Text>
        {onSave != null && value.hasValue && (
          <Button
            compact
            icon={editing ? 'close' : 'edit'}
            disabled={busy}
            onPress={() => {
              setEditing((e) => !e);
              setError(null);
              if (!editing) setDraft(text);
            }}
          >
            {editing ? 'Cancel' : hasText ? 'Edit' : 'Add'}
          </Button>
        )}
      </View>
      {caption != null && <Text style={{ fontSize: 11, color: colors.outline }}>{caption}</Text>}
      <View style={{ height: 8 }} />
      {!value.hasValue && value.hasError ? (
        <View style={{ flexDirection: 'row', alignItems: 'center' }}>
          <Text style={{ flex: 1, color: colors.error, fontSize: 13 }}>{describeError(value.error)}</Text>
          {onRetry && <Button onPress={onRetry}>Retry</Button>}
        </View>
      ) : !value.hasValue ? (
        <ProgressBar indeterminate style={{ height: 2 }} />
      ) : editing ? (
        <>
          <TextField value={draft} onChangeText={setDraft} autoFocus multiline minLines={3} placeholder={hint} autoCapitalize="sentences" />
          {error != null && <Text style={{ marginTop: 8, color: colors.error, fontSize: 13 }}>{error}</Text>}
          <View style={{ marginTop: 8, alignItems: 'flex-end' }}>
            <Button mode="contained" disabled={busy} onPress={save}>
              {busy ? <ActivityIndicator size={18} /> : 'Save'}
            </Button>
          </View>
        </>
      ) : (
        <>
          <Text selectable style={{ color: hasText ? colors.onSurface : colors.outline }}>
            {hasText ? text : emptyText}
          </Text>
          {hasText && updatedAt != null && (
            <Text style={{ marginTop: 6, fontSize: 11, color: colors.outline }}>Updated {format(updatedAt, 'MMM d, y')}</Text>
          )}
        </>
      )}
    </View>
  );
}
