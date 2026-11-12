import { useQueryClient } from '@tanstack/react-query';
import { format } from 'date-fns';
import { useState } from 'react';
import { View } from 'react-native';
import { ActivityIndicator, Button, Dialog, IconButton, ProgressBar, Text } from 'react-native-paper';

import type { Appointment } from '../models/appointment';
import type { Doctor } from '../models/doctor';
import type { Patient } from '../models/patient';
import { maxRxItems, type Prescription, type RxItem, rxItemProblem, rxItemTitle } from '../models/prescription';
import { printHtml } from '../platform/browser';
import { useCurrentDoctor } from '../queries/catalog';
import { useCanSeeClinicalNotes, useCurrentClinicRole } from '../queries/clinical';
import { useCurrentClinic } from '../queries/clinic';
import { invalidatePrescriptions, usePatientPrescriptions, useVisitPrescriptions } from '../queries/prescriptions';
import { buildPrescriptionHtml } from '../rx/prescription_print';
import { useRepository } from '../state/platform';
import { clinicImageUrl } from '../theme/brand';
import { useAppTheme } from '../theme/clinic_theme';
import { describeError } from '../ui/async_view';
import { TextField } from '../ui/fields';
import { Icon } from '../ui/icon';
import { type Close, SheetScroll, useOverlay } from '../ui/overlay';
import { ReasonDialog } from './ledger_view';

/// Opens the print dialog on one prescription, to print or save as a PDF.
export function usePrintPrescription(): (patient: Patient, rx: Prescription) => void {
  const clinic = useCurrentClinic().value ?? null;
  const overlay = useOverlay();
  return (patient, rx) => {
    if (clinic == null) return;
    const opened = printHtml(buildPrescriptionHtml({ clinic, patient, rx, logoSrc: clinicImageUrl }));
    if (!opened) overlay.snack('Printing works in the web app.');
  };
}

/// The prescriptions written at [appointment], or on [patient]'s chart when
/// there is no visit, for the clinic's doctors and admins. A doctor on the
/// roster writes one here; its doctor or an admin voids one. Renders nothing
/// for anyone else — the front desk does not read prescriptions.
export function PrescriptionsSection({ patient, appointment }: { patient: Patient; appointment?: Appointment }) {
  const allowed = useCanSeeClinicalNotes().value ?? false;
  if (!allowed) return null;
  return appointment == null ? <ChartPrescriptions patient={patient} /> : <VisitPrescriptions patient={patient} appointment={appointment} />;
}

function VisitPrescriptions({ patient, appointment }: { patient: Patient; appointment: Appointment }) {
  return <PrescriptionsCard patient={patient} appointment={appointment} list={useVisitPrescriptions(appointment.id)} />;
}

function ChartPrescriptions({ patient }: { patient: Patient }) {
  return <PrescriptionsCard patient={patient} list={usePatientPrescriptions(patient.id)} />;
}

function PrescriptionsCard({
  patient,
  appointment,
  list,
}: {
  patient: Patient;
  appointment?: Appointment;
  list: ReturnType<typeof usePatientPrescriptions>;
}) {
  const { colors } = useAppTheme();
  const qc = useQueryClient();
  const overlay = useOverlay();
  const repo = useRepository();
  const me = useCurrentDoctor().value ?? null;
  const isAdmin = useCurrentClinicRole().value === 'admin';
  const print = usePrintPrescription();

  const write = async () => {
    if (me == null) return;
    const id = await overlay.showSheet<string>((close) => <WritePrescriptionSheet patient={patient} appointment={appointment} doctor={me} close={close} />);
    if (id == null) return;
    await invalidatePrescriptions(qc);
    overlay.snack('Prescription written');
  };

  const voidOne = async (rx: Prescription) => {
    const reason = await overlay.showDialog<string>((close) => (
      <ReasonDialog
        title="Void this prescription?"
        message="The patient stops seeing it. It stays on the chart, marked void; write a new one if they still need medicine."
        hint="Why — e.g. wrong dose"
        action="Void"
        close={close}
      />
    ));
    if (reason == null) return;
    try {
      await repo.voidPrescription(rx.id, reason);
      overlay.snack('Prescription voided');
    } catch (e) {
      overlay.snack(describeError(e));
    } finally {
      void invalidatePrescriptions(qc);
    }
  };

  const editLicences = async () => {
    if (me == null) return;
    const saved = await overlay.showDialog<boolean>((close) => <LicenceDialog doctor={me} close={close} />);
    if (saved) {
      void qc.invalidateQueries({ queryKey: ['myDoctors'] });
      void qc.invalidateQueries({ queryKey: ['doctors'] });
    }
  };

  return (
    <View style={{ marginBottom: 12, padding: 16, borderRadius: 16, backgroundColor: colors.surfaceContainerLow }}>
      <View style={{ flexDirection: 'row', alignItems: 'center', gap: 6 }}>
        <Icon name="medication" size={16} color={colors.onSurfaceVariant} />
        <Text style={{ flex: 1, fontWeight: '600', color: colors.onSurfaceVariant, fontSize: 12 }}>Prescriptions</Text>
        {me != null && (
          <Button compact icon="add" onPress={() => void write()}>
            Write
          </Button>
        )}
      </View>
      {me != null && (me.prcLicenseNo == null || me.prcLicenseNo.trim() === '') && (
        <View style={{ flexDirection: 'row', alignItems: 'center', marginTop: 4 }}>
          <Text style={{ flex: 1, fontSize: 12, color: colors.outline }}>Your PRC licence number is not on your prescriptions yet.</Text>
          <Button compact onPress={() => void editLicences()}>
            Add
          </Button>
        </View>
      )}
      <View style={{ height: 8 }} />
      {!list.hasValue && list.hasError ? (
        <View style={{ flexDirection: 'row', alignItems: 'center' }}>
          <Text style={{ flex: 1, color: colors.error, fontSize: 13 }}>{describeError(list.error)}</Text>
          <Button onPress={() => void invalidatePrescriptions(qc)}>Retry</Button>
        </View>
      ) : !list.hasValue ? (
        <ProgressBar indeterminate style={{ height: 2 }} />
      ) : list.value!.length === 0 ? (
        <Text style={{ color: colors.outline }}>{appointment == null ? 'No prescriptions on file.' : 'No prescriptions at this visit.'}</Text>
      ) : (
        <View style={{ gap: 8 }}>
          {list.value!.map((rx) => (
            <PrescriptionView
              key={rx.id}
              rx={rx}
              onPrint={() => print(patient, rx)}
              onVoid={!rx.isVoid && (isAdmin || rx.doctorId === me?.id) ? () => void voidOne(rx) : undefined}
            />
          ))}
        </View>
      )}
    </View>
  );
}

/// One prescription: when and by whom, each medicine with its count and
/// instructions, the notes. Staff and the patient both see it this way.
export function PrescriptionView({ rx, onPrint, onVoid }: { rx: Prescription; onPrint?: () => void; onVoid?: () => void }) {
  const { colors } = useAppTheme();
  const strike = rx.isVoid ? ('line-through' as const) : ('none' as const);
  return (
    <View style={{ padding: 12, borderRadius: 12, backgroundColor: colors.surface, borderWidth: 1, borderColor: colors.outlineVariant }}>
      <View style={{ flexDirection: 'row', alignItems: 'center' }}>
        <View style={{ flex: 1 }}>
          <Text style={{ fontWeight: '600' }}>{format(rx.issuedAt, 'MMM d, y')}</Text>
          <Text style={{ fontSize: 12, color: colors.onSurfaceVariant }}>Dr. {rx.doctorName}</Text>
        </View>
        {onPrint != null && <IconButton icon="print" size={20} accessibilityLabel="Print" onPress={onPrint} />}
        {onVoid != null && <IconButton icon="block" size={20} accessibilityLabel="Void" onPress={onVoid} />}
      </View>
      {rx.isVoid && <Text style={{ fontSize: 12, color: colors.error }}>Void{rx.voidReason != null ? `: ${rx.voidReason}` : ''}</Text>}
      {rx.items.map((i, n) => (
        <View key={n} style={{ marginTop: 8 }}>
          <View style={{ flexDirection: 'row', gap: 8 }}>
            <Text style={{ flex: 1, fontWeight: '600', textDecorationLine: strike }}>{rxItemTitle(i)}</Text>
            {i.quantity != null && <Text style={{ fontWeight: '600', textDecorationLine: strike }}>#{i.quantity}</Text>}
          </View>
          <Text style={{ color: colors.onSurfaceVariant, textDecorationLine: strike }}>{i.sig}</Text>
        </View>
      ))}
      {rx.notes != null && rx.notes.trim() !== '' && <Text style={{ marginTop: 8, fontStyle: 'italic', color: colors.onSurfaceVariant }}>{rx.notes}</Text>}
    </View>
  );
}

type Draft = { drug: string; brand: string; strength: string; form: string; quantity: string; sig: string };
const blank: Draft = { drug: '', brand: '', strength: '', form: '', quantity: '', sig: '' };

function toItem(d: Draft): RxItem {
  const q = d.quantity.trim();
  return {
    drug: d.drug,
    brand: d.brand,
    strength: d.strength,
    form: d.form,
    quantity: q === '' ? null : Number(q),
    sig: d.sig,
  };
}

/// Writes a prescription in [doctor]'s name. Answers its id once saved.
function WritePrescriptionSheet({
  patient,
  appointment,
  doctor,
  close,
}: {
  patient: Patient;
  appointment?: Appointment;
  doctor: Doctor;
  close: Close<string>;
}) {
  const { colors } = useAppTheme();
  const repo = useRepository();
  const [drafts, setDrafts] = useState<Draft[]>([blank]);
  const [notes, setNotes] = useState('');
  const [busy, setBusy] = useState(false);
  const [tried, setTried] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const problems = drafts.map((d) => rxItemProblem(toItem(d)));
  const valid = problems.every((p) => p == null);

  const set = (n: number, patch: Partial<Draft>) => setDrafts((list) => list.map((d, i) => (i === n ? { ...d, ...patch } : d)));

  const save = async () => {
    setTried(true);
    if (!valid || busy) return;
    setBusy(true);
    setError(null);
    try {
      const id = await repo.writePrescription({
        clinicId: patient.clinicId,
        patientId: patient.id,
        doctorId: doctor.id,
        appointmentId: appointment?.id ?? null,
        items: drafts.map(toItem),
        notes,
      });
      close(id);
    } catch (e) {
      setError(describeError(e));
    } finally {
      setBusy(false);
    }
  };

  return (
    <SheetScroll padding={20}>
      <Text variant="titleLarge" style={{ fontWeight: '700' }}>
        Write a prescription
      </Text>
      <Text style={{ marginTop: 4, color: colors.onSurfaceVariant }}>
        For {patient.name} · Dr. {doctor.name}
      </Text>
      {drafts.map((d, n) => (
        <View key={n} style={{ marginTop: 16, padding: 12, borderRadius: 12, borderWidth: 1, borderColor: colors.outlineVariant, gap: 8 }}>
          <View style={{ flexDirection: 'row', alignItems: 'center' }}>
            <Text style={{ flex: 1, fontWeight: '600' }}>Medicine {n + 1}</Text>
            {drafts.length > 1 && (
              <IconButton icon="delete-outline" size={20} accessibilityLabel="Remove" onPress={() => setDrafts((list) => list.filter((_, i) => i !== n))} />
            )}
          </View>
          <TextField label="Generic name" value={d.drug} onChangeText={(v) => set(n, { drug: v })} autoCapitalize="words" maxLength={200} />
          <TextField label="Brand (optional)" value={d.brand} onChangeText={(v) => set(n, { brand: v })} autoCapitalize="words" maxLength={200} />
          <View style={{ flexDirection: 'row', gap: 8 }}>
            <View style={{ flex: 1 }}>
              <TextField label="Strength" placeholder="500 mg" value={d.strength} onChangeText={(v) => set(n, { strength: v })} maxLength={100} />
            </View>
            <View style={{ flex: 1 }}>
              <TextField label="Form" placeholder="capsule" value={d.form} onChangeText={(v) => set(n, { form: v })} maxLength={100} />
            </View>
            <View style={{ width: 88 }}>
              <TextField
                label="Qty"
                placeholder="21"
                keyboardType="number-pad"
                value={d.quantity}
                onChangeText={(v) => set(n, { quantity: v.replace(/[^0-9]/g, '') })}
                maxLength={4}
              />
            </View>
          </View>
          <TextField
            label="Instructions (Sig)"
            placeholder="1 capsule 3 times a day for 7 days"
            value={d.sig}
            onChangeText={(v) => set(n, { sig: v })}
            multiline
            autoCapitalize="sentences"
            maxLength={500}
          />
          {tried && problems[n] != null && <Text style={{ color: colors.error, fontSize: 12 }}>{problems[n]}</Text>}
        </View>
      ))}
      {drafts.length < maxRxItems && (
        <Button icon="add" mode="outlined" onPress={() => setDrafts((list) => [...list, blank])} style={{ marginTop: 12, alignSelf: 'flex-start' }}>
          Add medicine
        </Button>
      )}
      <View style={{ marginTop: 16 }}>
        <TextField
          label="Notes (optional)"
          placeholder="Take with food. Follow up in 1 week."
          value={notes}
          onChangeText={setNotes}
          multiline
          autoCapitalize="sentences"
          maxLength={1000}
        />
      </View>
      <Text style={{ marginTop: 8, fontSize: 12, color: colors.outline }}>
        A prescription cannot be edited once written. To correct one, void it and write a new one.
      </Text>
      {error != null && <Text style={{ marginTop: 8, color: colors.error }}>{error}</Text>}
      <View style={{ flexDirection: 'row', justifyContent: 'flex-end', gap: 8, marginTop: 16 }}>
        <Button onPress={() => close()}>Cancel</Button>
        <Button mode="contained" disabled={busy || (tried && !valid)} onPress={() => void save()}>
          {busy ? <ActivityIndicator size={18} /> : 'Write prescription'}
        </Button>
      </View>
    </SheetScroll>
  );
}

/// A doctor's PRC, PTR and S2 numbers, as printed on their prescriptions.
/// The doctor edits their own; an admin anyone's.
export function LicenceDialog({ doctor, close }: { doctor: Doctor; close: Close<boolean> }) {
  const { colors } = useAppTheme();
  const repo = useRepository();
  const [prc, setPrc] = useState(doctor.prcLicenseNo ?? '');
  const [ptr, setPtr] = useState(doctor.ptrNo ?? '');
  const [s2, setS2] = useState(doctor.s2LicenseNo ?? '');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const save = async () => {
    setBusy(true);
    setError(null);
    try {
      await repo.updateDoctor(doctor.id, {
        prc_license_no: prc.trim() || null,
        ptr_no: ptr.trim() || null,
        s2_license_no: s2.trim() || null,
      });
      close(true);
    } catch (e) {
      setError(describeError(e));
    } finally {
      setBusy(false);
    }
  };

  return (
    <>
      <Dialog.Title>Licence numbers</Dialog.Title>
      <Dialog.Content style={{ gap: 12 }}>
        <Text style={{ color: colors.onSurfaceVariant }}>Printed under Dr. {doctor.name}'s name on every prescription.</Text>
        <TextField label="PRC licence no." value={prc} onChangeText={setPrc} maxLength={40} />
        <TextField label="PTR no." value={ptr} onChangeText={setPtr} maxLength={40} />
        <TextField label="S2 licence no. (dangerous drugs)" value={s2} onChangeText={setS2} maxLength={40} />
        {error != null && <Text style={{ color: colors.error }}>{error}</Text>}
      </Dialog.Content>
      <Dialog.Actions>
        <Button onPress={() => close()}>Cancel</Button>
        <Button mode="contained" disabled={busy} onPress={() => void save()}>
          Save
        </Button>
      </Dialog.Actions>
    </>
  );
}
