import { useQueryClient } from '@tanstack/react-query';
import { format } from 'date-fns';
import { useState } from 'react';
import { Image, Pressable, View } from 'react-native';
import { ActivityIndicator, Button, Chip, Dialog, ProgressBar, Switch, Text } from 'react-native-paper';

import type { Appointment } from '../models/appointment';
import {
  type AttachmentKind,
  attachmentKindMeta,
  attachmentKinds,
  attachmentMimeTypes,
  attachmentProblem,
  type ChartAttachment,
  formatBytes,
} from '../models/attachment';
import type { Patient } from '../models/patient';
import { inBrowser, openExternal, type PickedFile, pickFile } from '../platform/browser';
import { invalidateAttachments, useAttachmentUrl, usePatientAttachments } from '../queries/attachments';
import { useCanSeeClinicalNotes } from '../queries/clinical';
import { useRepository } from '../state/platform';
import { useAppTheme } from '../theme/clinic_theme';
import { describeError } from '../ui/async_view';
import { DateField, TextField } from '../ui/fields';
import { Icon } from '../ui/icon';
import { type Close, useOverlay } from '../ui/overlay';
import { Page } from '../ui/page';
import { startOfDay } from '../util/dates';

/// A chart's x-rays, photos and documents, for its clinicians: upload (in the
/// web app), look, caption, share with the patient, delete. On a visit, the
/// files from that visit. Renders nothing for anyone else.
export function AttachmentsSection({ patient, appointment }: { patient: Patient; appointment?: Appointment }) {
  const { colors } = useAppTheme();
  const qc = useQueryClient();
  const overlay = useOverlay();
  const allowed = useCanSeeClinicalNotes().value ?? false;
  const all = usePatientAttachments(patient.id);
  const open = useOpenAttachment(true);
  if (!allowed) return null;
  const list = appointment == null ? all.value : all.value?.filter((a) => a.appointmentId === appointment.id);

  const upload = async () => {
    const file = await pickFile(attachmentMimeTypes.join(','));
    if (file == null) return;
    const problem = attachmentProblem(file);
    if (problem != null) {
      overlay.snack(problem);
      return;
    }
    const saved = await overlay.showDialog<boolean>((close) => <UploadDialog patient={patient} appointment={appointment} file={file} close={close} />, {
      dismissible: false,
    });
    if (saved) {
      await invalidateAttachments(qc);
      overlay.snack('File added');
    }
  };

  return (
    <View style={{ marginBottom: 12, padding: 16, borderRadius: 16, backgroundColor: colors.surfaceContainerLow }}>
      <View style={{ flexDirection: 'row', alignItems: 'center', gap: 6 }}>
        <Icon name="medical-information" size={16} color={colors.onSurfaceVariant} />
        <Text style={{ flex: 1, fontWeight: '600', color: colors.onSurfaceVariant, fontSize: 12 }}>X-rays & photos</Text>
        {inBrowser() && (
          <Button compact icon="upload-file" onPress={() => void upload()}>
            Add
          </Button>
        )}
      </View>
      <Text style={{ fontSize: 11, color: colors.outline }}>Doctors and admins only, unless shared with the patient.</Text>
      <View style={{ height: 8 }} />
      {!all.hasValue && all.hasError ? (
        <View style={{ flexDirection: 'row', alignItems: 'center' }}>
          <Text style={{ flex: 1, color: colors.error, fontSize: 13 }}>{describeError(all.error)}</Text>
          <Button onPress={() => void invalidateAttachments(qc)}>Retry</Button>
        </View>
      ) : list == null ? (
        <ProgressBar indeterminate style={{ height: 2 }} />
      ) : list.length === 0 ? (
        <Text style={{ color: colors.outline }}>{appointment == null ? 'No files on this chart.' : 'No files from this visit.'}</Text>
      ) : (
        <AttachmentGrid list={list} onOpen={open} />
      )}
    </View>
  );
}

/// Thumbnails, a few to a row.
export function AttachmentGrid({ list, onOpen }: { list: ChartAttachment[]; onOpen: (a: ChartAttachment) => void }) {
  return (
    <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 8 }}>
      {list.map((a) => (
        <AttachmentThumb key={a.id} attachment={a} onPress={() => onOpen(a)} />
      ))}
    </View>
  );
}

const thumbSize = 104;

function AttachmentThumb({ attachment: a, onPress }: { attachment: ChartAttachment; onPress: () => void }) {
  const { colors } = useAppTheme();
  const url = useAttachmentUrl(a).value;
  const meta = attachmentKindMeta[a.kind];
  return (
    <Pressable onPress={onPress} accessibilityLabel={`${meta.label}: ${a.caption ?? a.fileName}`} style={{ width: thumbSize }}>
      <View
        style={{
          width: thumbSize,
          height: thumbSize,
          borderRadius: 10,
          overflow: 'hidden',
          alignItems: 'center',
          justifyContent: 'center',
          backgroundColor: colors.surfaceContainerHighest,
        }}
      >
        {a.isImage && url != null ? (
          <Image source={{ uri: url }} style={{ width: thumbSize, height: thumbSize }} resizeMode="cover" />
        ) : (
          <Icon name={meta.icon} size={32} color={colors.onSurfaceVariant} />
        )}
        {a.sharedWithPatient && (
          <View style={{ position: 'absolute', top: 4, right: 4, borderRadius: 10, padding: 2, backgroundColor: colors.surface }}>
            <Icon name="people-outline" size={14} color={colors.primary} />
          </View>
        )}
      </View>
      <Text numberOfLines={1} style={{ fontSize: 11, marginTop: 2 }}>
        {a.caption ?? meta.label}
      </Text>
      <Text style={{ fontSize: 10, color: colors.onSurfaceVariant }}>{format(a.date, 'MMM d, y')}</Text>
    </Pressable>
  );
}

/// Opens one file full size. [manage]: a clinician's view, which can edit
/// and delete it.
export function useOpenAttachment(manage: boolean): (a: ChartAttachment) => void {
  const overlay = useOverlay();
  return (a) => void overlay.showPage((close) => <AttachmentViewer attachment={a} manage={manage} close={close} />);
}

function AttachmentViewer({ attachment: a, manage, close }: { attachment: ChartAttachment; manage: boolean; close: Close<void> }) {
  const { colors } = useAppTheme();
  const qc = useQueryClient();
  const overlay = useOverlay();
  const repo = useRepository();
  const url = useAttachmentUrl(a).value ?? null;
  const meta = attachmentKindMeta[a.kind];

  const edit = async () => {
    const saved = await overlay.showDialog<boolean>((c) => <EditDialog attachment={a} close={c} />);
    if (saved) {
      await invalidateAttachments(qc);
      close();
    }
  };

  const remove = async () => {
    const ok = await overlay.confirm({
      title: 'Delete this file?',
      message: 'It is removed from the chart for good. The activity log keeps a record that it was there.',
      confirmLabel: 'Delete',
      destructive: true,
    });
    if (!ok) return;
    try {
      await repo.deleteAttachment(a);
      await invalidateAttachments(qc);
      overlay.snack('File deleted');
      close();
    } catch (e) {
      overlay.snack(describeError(e));
    }
  };

  return (
    <Page
      title={a.caption ?? meta.label}
      subtitle={`${meta.label} · ${format(a.date, 'MMM d, y')} · ${formatBytes(a.sizeBytes)}`}
      actions={
        <>
          {url != null && inBrowser() && (
            <Button icon="download" onPress={() => openExternal(url)}>
              Open
            </Button>
          )}
          {manage && (
            <Button icon="edit" onPress={() => void edit()}>
              Edit
            </Button>
          )}
        </>
      }
    >
      <View style={{ gap: 12 }}>
        {url == null ? (
          <ActivityIndicator style={{ padding: 32 }} />
        ) : a.isImage ? (
          <Image source={{ uri: url }} style={{ width: '100%', aspectRatio: 4 / 3, backgroundColor: '#000', borderRadius: 12 }} resizeMode="contain" />
        ) : (
          <View style={{ alignItems: 'center', padding: 32, gap: 8 }}>
            <Icon name={meta.icon} size={48} color={colors.onSurfaceVariant} />
            <Text>{a.fileName}</Text>
            <Button mode="contained-tonal" icon="download" onPress={() => openExternal(url)}>
              Open the file
            </Button>
          </View>
        )}
        {manage && (
          <Text style={{ color: colors.onSurfaceVariant }}>
            {a.sharedWithPatient ? 'The patient can see this in their app.' : 'Not shared with the patient.'}
          </Text>
        )}
        {manage && (
          <Button icon="delete-outline" textColor={colors.error} style={{ alignSelf: 'flex-start' }} onPress={() => void remove()}>
            Delete
          </Button>
        )}
      </View>
    </Page>
  );
}

function UploadDialog({ patient, appointment, file, close }: { patient: Patient; appointment?: Appointment; file: PickedFile; close: Close<boolean> }) {
  const { colors } = useAppTheme();
  const repo = useRepository();
  const [kind, setKind] = useState<AttachmentKind>(file.type === 'application/pdf' ? 'document' : 'xray');
  const [caption, setCaption] = useState('');
  const [takenOn, setTakenOn] = useState<Date | null>(startOfDay(appointment?.dateTime ?? new Date()));
  const [shared, setShared] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const save = async () => {
    setBusy(true);
    setError(null);
    try {
      await repo.uploadAttachment({
        clinicId: patient.clinicId,
        patientId: patient.id,
        appointmentId: appointment?.id ?? null,
        kind,
        file,
        caption,
        takenOn,
        sharedWithPatient: shared,
      });
      close(true);
    } catch (e) {
      setError(describeError(e));
      setBusy(false);
    }
  };

  return (
    <>
      <Dialog.Title>Add to {patient.name}'s chart</Dialog.Title>
      <Dialog.Content style={{ gap: 12 }}>
        <Text style={{ color: colors.onSurfaceVariant }}>{`${file.name} · ${formatBytes(file.size)}`}</Text>
        <KindChips value={kind} onChange={setKind} />
        <TextField label="Caption (optional)" placeholder="Periapical, tooth 36" value={caption} onChangeText={setCaption} maxLength={500} />
        <DateField label="Taken on" value={takenOn} onChange={setTakenOn} max={new Date()} />
        <SharedSwitch value={shared} onChange={setShared} />
        {error != null && <Text style={{ color: colors.error }}>{error}</Text>}
      </Dialog.Content>
      <Dialog.Actions>
        <Button disabled={busy} onPress={() => close(false)}>
          Cancel
        </Button>
        <Button mode="contained" disabled={busy} onPress={() => void save()}>
          {busy ? <ActivityIndicator size={18} /> : 'Upload'}
        </Button>
      </Dialog.Actions>
    </>
  );
}

function EditDialog({ attachment: a, close }: { attachment: ChartAttachment; close: Close<boolean> }) {
  const { colors } = useAppTheme();
  const repo = useRepository();
  const [kind, setKind] = useState<AttachmentKind>(a.kind);
  const [caption, setCaption] = useState(a.caption ?? '');
  const [takenOn, setTakenOn] = useState<Date | null>(a.takenOn);
  const [shared, setShared] = useState(a.sharedWithPatient);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const save = async () => {
    setBusy(true);
    setError(null);
    try {
      await repo.updateAttachment(a.id, { kind, caption, takenOn, sharedWithPatient: shared });
      close(true);
    } catch (e) {
      setError(describeError(e));
      setBusy(false);
    }
  };

  return (
    <>
      <Dialog.Title>Edit file</Dialog.Title>
      <Dialog.Content style={{ gap: 12 }}>
        <KindChips value={kind} onChange={setKind} />
        <TextField label="Caption" value={caption} onChangeText={setCaption} maxLength={500} />
        <DateField label="Taken on" value={takenOn} onChange={setTakenOn} max={new Date()} />
        <SharedSwitch value={shared} onChange={setShared} />
        {error != null && <Text style={{ color: colors.error }}>{error}</Text>}
      </Dialog.Content>
      <Dialog.Actions>
        <Button onPress={() => close(false)}>Cancel</Button>
        <Button mode="contained" disabled={busy} onPress={() => void save()}>
          Save
        </Button>
      </Dialog.Actions>
    </>
  );
}

function KindChips({ value, onChange }: { value: AttachmentKind; onChange: (k: AttachmentKind) => void }) {
  return (
    <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 6 }}>
      {attachmentKinds.map((k) => (
        <Chip key={k} mode="outlined" selected={value === k} showSelectedCheck onPress={() => onChange(k)}>
          {attachmentKindMeta[k].label}
        </Chip>
      ))}
    </View>
  );
}

function SharedSwitch({ value, onChange }: { value: boolean; onChange: (v: boolean) => void }) {
  const { colors } = useAppTheme();
  return (
    <View style={{ flexDirection: 'row', alignItems: 'center', gap: 12 }}>
      <View style={{ flex: 1 }}>
        <Text>Share with the patient</Text>
        <Text style={{ fontSize: 12, color: colors.onSurfaceVariant }}>They see it in their app under X-rays & photos.</Text>
      </View>
      <Switch value={value} onValueChange={onChange} />
    </View>
  );
}
