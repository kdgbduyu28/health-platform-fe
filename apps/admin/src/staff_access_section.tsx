import {
  AppCard,
  type AppRole,
  AsyncView,
  Avatar,
  BarAction,
  Icon,
  ListTile,
  type StaffInvite,
  TextField,
  copyText,
  describeError,
  roleDisplayName,
  useAppTheme,
  useCurrentClinic,
  useCurrentClinicId,
  useDoctors,
  useOverlay,
  useRepository,
  useStaffInvites,
} from '@health/shared';
import { useQueryClient } from '@tanstack/react-query';
import { format } from 'date-fns';
import { useState } from 'react';
import { View } from 'react-native';
import { Button, Dialog, SegmentedButtons, Text } from 'react-native-paper';

import { SectionTitle } from './settings_bits';

/// New staff waiting for approval, and the single-use codes still unused.
///
/// Full admins and branch admins both run this: the database lets either
/// one issue doctor and assistant codes at their clinic and decide the
/// requests.
export function StaffAccessSection() {
  const { colors } = useAppTheme();
  const qc = useQueryClient();
  const overlay = useOverlay();
  const repo = useRepository();
  const clinicId = useCurrentClinicId();
  const clinic = useCurrentClinic().value ?? null;
  const invitesAsync = useStaffInvites();

  const copy = async (code: string) => overlay.snack((await copyText(code)) ? 'Code copied' : 'Could not copy the code');

  const newCode = async () => {
    const result = await overlay.showDialog<{ role: AppRole; label: string }>((close) => <NewCodeDialog close={close} />);
    if (result == null || clinicId == null) return;
    try {
      const invite = await repo.createStaffInvite({ clinicId, role: result.role, label: result.label === '' ? null : result.label });
      void qc.invalidateQueries({ queryKey: ['staffInvites'] });
      await overlay.showDialog<void>((close) => <CodeIssuedDialog invite={invite} onCopy={() => void copy(invite.code)} close={close} />);
    } catch (e) {
      overlay.snack(describeError(e));
    }
  };

  const revoke = async (invite: StaffInvite) => {
    const ok = await overlay.confirm({
      title: `Cancel code ${invite.code}?`,
      message: 'It stops working straight away. You can issue a new one.',
      cancelLabel: 'Back',
      confirmLabel: 'Cancel code',
      destructive: true,
    });
    if (!ok) return;
    try {
      await repo.revokeStaffInvite(invite.id);
      void qc.invalidateQueries({ queryKey: ['staffInvites'] });
      overlay.snack('Code cancelled');
    } catch (e) {
      overlay.snack(describeError(e));
    }
  };

  const decide = async (request: StaffInvite, approve: boolean) => {
    const role = roleDisplayName(request.role).toLowerCase();
    let doctorId: string | null = null;
    let specialty: string | null = null;
    if (approve && request.role === 'doctor') {
      const choice = await overlay.showDialog<{ doctorId: string | null; specialty: string | null }>((close) => (
        <ApproveDoctorDialog request={request} close={close} />
      ));
      if (choice == null) return;
      ({ doctorId, specialty } = choice);
    } else {
      const ok = await overlay.confirm({
        title: approve ? `Approve ${request.applicant}?` : `Decline ${request.applicant}?`,
        message: approve
          ? `They join ${clinic?.name ?? 'this clinic'} as ${role} and can see its appointments and patients straight away.`
          : 'They will not get access. The code cannot be used again; issue a new one if this was a mistake.',
        cancelLabel: 'Back',
        confirmLabel: approve ? 'Approve' : 'Decline',
        destructive: !approve,
      });
      if (!ok) return;
    }
    try {
      await repo.decideStaffRequest({ inviteId: request.id, approve, doctorId, specialty });
      for (const k of ['staffInvites', 'staff', 'doctors', 'roster']) void qc.invalidateQueries({ queryKey: [k] });
      overlay.snack(approve ? `${request.applicant} joined as ${role}` : `Request from ${request.applicant} declined`);
    } catch (e) {
      overlay.snack(describeError(e));
    }
  };

  return (
    <View>
      <SectionTitle
        action={
          <Button icon="key" onPress={() => void newCode()}>
            New code
          </Button>
        }
      >
        Staff requests
      </SectionTitle>
      <AsyncView value={invitesAsync} padded onRetry={() => void qc.invalidateQueries({ queryKey: ['staffInvites'] })}>
        {(invites) => {
          const now = new Date();
          const pending = invites.filter((i) => i.status === 'pending');
          const unused = invites.filter((i) => i.status === 'open' && !i.isExpired(now));
          if (pending.length === 0 && unused.length === 0) {
            return (
              <Text style={{ color: colors.onSurfaceVariant }}>
                Give each new doctor or assistant their own code. They enter it after creating an account, and their request shows up here for you to
                approve.
              </Text>
            );
          }
          return (
            <View style={{ gap: 8 }}>
              {pending.map((r) => (
                <RequestCard key={r.id} request={r} onApprove={() => void decide(r, true)} onDecline={() => void decide(r, false)} />
              ))}
              {unused.length > 0 && (
                <Text variant="labelLarge" style={{ color: colors.onSurfaceVariant, paddingHorizontal: 4, paddingTop: 12 }}>
                  Unused codes
                </Text>
              )}
              {unused.map((invite) => (
                <AppCard key={invite.id}>
                  <ListTile
                    leading={<Icon name="key" />}
                    title={<Text style={{ fontWeight: '600', letterSpacing: 3 }}>{invite.code}</Text>}
                    subtitle={[
                      roleDisplayName(invite.role),
                      ...(invite.label != null ? [`for ${invite.label}`] : []),
                      `expires ${format(invite.expiresAt, 'MMM d')}`,
                    ].join(' · ')}
                    trailing={
                      <View style={{ flexDirection: 'row' }}>
                        <BarAction icon="content-copy" label="Copy code" onPress={() => void copy(invite.code)} />
                        <BarAction icon="block" label="Cancel code" onPress={() => void revoke(invite)} />
                      </View>
                    }
                  />
                </AppCard>
              ))}
            </View>
          );
        }}
      </AsyncView>
    </View>
  );
}

function RequestCard({ request, onApprove, onDecline }: { request: StaffInvite; onApprove: () => void; onDecline: () => void }) {
  const { colors } = useAppTheme();
  const details = [
    `Wants to join as ${roleDisplayName(request.role).toLowerCase()}`,
    ...(request.redeemerEmail != null ? [request.redeemerEmail] : []),
    ...(request.label != null ? [`code issued for ${request.label}`] : []),
  ];
  return (
    <AppCard style={{ paddingTop: 4, paddingBottom: 8, paddingRight: 12 }}>
      <ListTile
        leading={<Avatar icon="hourglass-top" color={colors.tertiaryContainer} textColor={colors.onTertiaryContainer} />}
        title={request.applicant}
        subtitle={details.join(' · ')}
      />
      <View style={{ flexDirection: 'row', justifyContent: 'flex-end', gap: 8 }}>
        <Button onPress={onDecline}>Decline</Button>
        <Button mode="contained" onPress={onApprove}>
          Approve
        </Button>
      </View>
    </AppCard>
  );
}

function NewCodeDialog({ close }: { close: (v?: { role: AppRole; label: string }) => void }) {
  const { colors } = useAppTheme();
  const [role, setRole] = useState<AppRole>('doctor');
  const [label, setLabel] = useState('');
  return (
    <>
      <Dialog.Title>New staff code</Dialog.Title>
      <Dialog.Content>
        <SegmentedButtons
          value={role}
          onValueChange={(v) => setRole(v as AppRole)}
          buttons={[
            { value: 'doctor', label: 'Doctor' },
            { value: 'assistant', label: 'Assistant' },
          ]}
        />
        <TextField style={{ marginTop: 16 }} label="Who is it for? (optional)" placeholder="e.g. Dr. Reyes" autoCapitalize="words" value={label} onChangeText={setLabel} />
        <Text style={{ marginTop: 16, fontSize: 12, color: colors.onSurfaceVariant }}>One code per person. It works once and expires in 7 days.</Text>
      </Dialog.Content>
      <Dialog.Actions>
        <Button onPress={() => close()}>Cancel</Button>
        <Button mode="contained" onPress={() => close({ role, label: label.trim() })}>
          Create
        </Button>
      </Dialog.Actions>
    </>
  );
}

function CodeIssuedDialog({ invite, onCopy, close }: { invite: StaffInvite; onCopy: () => void; close: () => void }) {
  const { colors } = useAppTheme();
  const role = roleDisplayName(invite.role);
  const who = invite.label ?? `the new ${role.toLowerCase()}`;
  return (
    <>
      <Dialog.Title>Staff code ready</Dialog.Title>
      <Dialog.Content>
        <View style={{ flexDirection: 'row', alignItems: 'center' }}>
          <Text selectable variant="headlineMedium" style={{ flex: 1, fontWeight: '700', letterSpacing: 6, color: colors.primary }}>
            {invite.code}
          </Text>
          <BarAction icon="content-copy" label="Copy code" onPress={onCopy} />
        </View>
        <Text style={{ marginTop: 12, color: colors.onSurfaceVariant, lineHeight: 20 }}>
          Give this to {who}. They create an account in the {role} app, sign in, and enter it. It works once and expires{' '}
          {format(invite.expiresAt, 'MMM d')}. You approve them here afterwards.
        </Text>
      </Dialog.Content>
      <Dialog.Actions>
        <Button mode="contained" onPress={close}>
          Done
        </Button>
      </Dialog.Actions>
    </>
  );
}

/// Approving a doctor also puts them on the roster: link a roster entry the
/// clinic already has, or create one. Answers (doctorId, specialty) —
/// exactly one of them set.
function ApproveDoctorDialog({
  request,
  close,
}: {
  request: StaffInvite;
  close: (v?: { doctorId: string | null; specialty: string | null }) => void;
}) {
  const { colors } = useAppTheme();
  const unlinked = (useDoctors().value ?? []).filter((d) => d.profileId == null);
  /// Null means "create a new roster entry".
  const [doctorId, setDoctorId] = useState<string | null>(null);
  const [specialty, setSpecialty] = useState('');
  const [error, setError] = useState<string | null>(null);

  const option = (id: string | null, title: string, subtitle?: string) => {
    const on = doctorId === id;
    return (
      <ListTile
        key={id ?? 'new'}
        paddingHorizontal={0}
        selected={on}
        leading={<Icon name={on ? 'radio-button-checked' : 'radio-button-unchecked'} color={on ? colors.primary : undefined} />}
        title={title}
        subtitle={subtitle}
        onPress={() => setDoctorId(id)}
      />
    );
  };

  return (
    <>
      <Dialog.Title>Approve {request.applicant}</Dialog.Title>
      <Dialog.ScrollArea style={{ paddingHorizontal: 24 }}>
        <Text style={{ marginTop: 8, color: colors.onSurfaceVariant, lineHeight: 20 }}>
          Which roster entry is theirs? Patients book against the roster, so an entry the clinic already has keeps its appointments and schedule.
        </Text>
        <View style={{ height: 8 }} />
        {unlinked.map((d) => option(d.id, d.name, d.specialty))}
        {option(null, 'Add a new roster entry')}
        {doctorId == null && (
          <TextField label="Specialty" placeholder="e.g. Orthodontics" autoCapitalize="words" value={specialty} onChangeText={setSpecialty} error={error} />
        )}
        <View style={{ height: 8 }} />
      </Dialog.ScrollArea>
      <Dialog.Actions>
        <Button onPress={() => close()}>Cancel</Button>
        <Button
          mode="contained"
          onPress={() => {
            if (doctorId == null && specialty.trim() === '') {
              setError('Enter their specialty');
              return;
            }
            close(doctorId == null ? { doctorId: null, specialty: specialty.trim() } : { doctorId, specialty: null });
          }}
        >
          Approve
        </Button>
      </Dialog.Actions>
    </>
  );
}
