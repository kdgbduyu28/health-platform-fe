import {
  AccountMenuButton,
  AppCard,
  type AppRole,
  AsyncView,
  Avatar,
  BarAction,
  Brand,
  type Clinic,
  type ClinicMembership,
  ClinicMark,
  ContentWidth,
  Icon,
  type IconName,
  ListTile,
  NotificationsButton,
  Page,
  SelectField,
  TextField,
  Wrap,
  copyText,
  describeError,
  initialsOf,
  parseHexColor,
  roleDisplayName,
  useAppTheme,
  useCatalogue,
  useClinicNav,
  useCurrentClinic,
  useCurrentClinicId,
  useCurrentUserId,
  useIsFullAdmin,
  useOverlay,
  useRepository,
  useRoster,
  useStaff,
  useTimeOff,
} from '@health/shared';
import { useQueryClient } from '@tanstack/react-query';
import { Fragment, useState } from 'react';
import { View } from 'react-native';
import { Button, Dialog, Divider, SegmentedButtons, Text } from 'react-native-paper';

import { ClinicPageTitle } from './clinic_page_title';
import { SwitchRow } from './roster_widgets';
import { SectionTitle } from './settings_bits';
import { StaffAccessSection } from './staff_access_section';

/// The clinic's own settings, run by its admins: how it presents itself,
/// how patients get in, and who works there.
///
/// All of it is self-service by design. The database lets an admin change
/// exactly these things for their own clinic — not its type, slug or active
/// status, which stay with the platform operator.
export function ClinicSettingsScreen() {
  const nav = useClinicNav();
  const clinic = useCurrentClinic().value ?? null;
  return (
    <Page
      title={<ClinicPageTitle label="Clinic settings" />}
      maxWidth={ContentWidth.list}
      actions={
        <>
          <BarAction icon="history" label="Activity log" onPress={() => nav.push('/activity')} />
          <NotificationsButton />
          <AccountMenuButton />
        </>
      }
    >
      {clinic != null && (
        <View style={{ gap: 24 }}>
          <DetailsCard clinic={clinic} />
          <View>
            <SectionTitle>Bookings</SectionTitle>
            <BookingsCard />
          </View>
          <View>
            <SectionTitle>Patient join code</SectionTitle>
            <JoinCodeCard clinic={clinic} />
          </View>
          <StaffAccessSection />
          <StaffSection />
          <View>
            <SectionTitle>Activity</SectionTitle>
            <AppCard>
              <ListTile
                leading={<Icon name="history" />}
                title="Activity log"
                subtitle="Who changed what, and when: patients, visits, bills and settings"
                trailing={<Icon name="chevron-right" />}
                onPress={() => nav.push('/activity')}
              />
            </AppCard>
          </View>
        </View>
      )}
    </Page>
  );
}

// ── Details ─────────────────────────────────────────────────────────────────

function InfoLine({ icon, text }: { icon: IconName; text: string }) {
  const { colors } = useAppTheme();
  return (
    <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8, paddingVertical: 4 }}>
      <Icon name={icon} size={16} color={colors.primary} />
      <Text style={{ flex: 1 }}>{text}</Text>
    </View>
  );
}

function DetailsCard({ clinic }: { clinic: Clinic }) {
  const { colors } = useAppTheme();
  const qc = useQueryClient();
  const overlay = useOverlay();
  const repo = useRepository();

  const edit = async () => {
    const changes = await overlay.showDialog<Record<string, unknown>>((close) => <EditDetailsDialog clinic={clinic} close={close} />, {
      dismissible: false,
    });
    if (changes == null) return;
    try {
      await repo.updateClinic(clinic.id, changes);
      void qc.invalidateQueries({ queryKey: ['visibleClinics'] });
      overlay.snack('Clinic details saved');
    } catch (e) {
      overlay.snack(describeError(e));
    }
  };

  return (
    <AppCard padding={16}>
      <View style={{ flexDirection: 'row', alignItems: 'center', gap: 16 }}>
        <ClinicMark clinic={clinic} size={56} />
        <View style={{ flex: 1 }}>
          <Text variant="titleLarge" style={{ fontWeight: '700' }}>
            {clinic.name}
          </Text>
          <Text style={{ color: colors.onSurfaceVariant }}>{clinic.typeName}</Text>
        </View>
        <BarAction icon="edit" label="Edit details" onPress={() => void edit()} />
      </View>
      <Divider style={{ marginVertical: 12 }} />
      {clinic.contactPhone != null && <InfoLine icon="phone" text={clinic.contactPhone} />}
      {clinic.address != null && <InfoLine icon="place" text={clinic.address} />}
      <InfoLine icon="event-repeat" text={`Recall patients ${clinic.recallMonths} months after their last visit`} />
    </AppCard>
  );
}

const orNull = (s: string) => (s.trim() === '' ? null : s.trim());

/// Answers the changed columns, or nothing if cancelled.
function EditDetailsDialog({ clinic, close }: { clinic: Clinic; close: (changes?: Record<string, unknown>) => void }) {
  const [name, setName] = useState(clinic.name);
  const [color, setColor] = useState(clinic.seedColor ?? '');
  const [logo, setLogo] = useState(clinic.logoUrl ?? '');
  const [phone, setPhone] = useState(clinic.contactPhone ?? '');
  const [address, setAddress] = useState(clinic.address ?? '');
  const [recallMonths, setRecallMonths] = useState(clinic.recallMonths);
  const [errors, setErrors] = useState<{ name?: string; color?: string; logo?: string }>({});
  const preview = parseHexColor(color);
  const recallOptions = [...new Set([3, 4, 6, 9, 12, 18, 24, recallMonths])].sort((a, b) => a - b);

  const save = () => {
    const url = logo.trim();
    const errs = {
      name: name.trim() === '' ? 'Enter a name' : undefined,
      color: color.trim() !== '' && preview == null ? 'Use #RRGGBB, e.g. #1F8A70' : undefined,
      logo: url === '' || url.startsWith('https://') || url.startsWith(Brand.bundledAssetScheme) ? undefined : 'Use an https:// link',
    };
    setErrors(errs);
    if (errs.name != null || errs.color != null || errs.logo != null) return;
    close({
      name: name.trim(),
      seed_color: preview,
      logo_url: orNull(logo),
      contact_phone: orNull(phone),
      address: orNull(address),
      // Only when changed, so saving the other details never depends on it.
      ...(recallMonths !== clinic.recallMonths ? { recall_months: recallMonths } : {}),
    });
  };

  return (
    <>
      <Dialog.Title>Clinic details</Dialog.Title>
      <Dialog.ScrollArea style={{ paddingHorizontal: 24 }}>
        <View style={{ gap: 12, paddingVertical: 8 }}>
          <TextField label="Clinic name" value={name} onChangeText={setName} autoCapitalize="words" error={errors.name} />
          <TextField
            label="Brand colour"
            placeholder="#1F8A70"
            helperText="Leave empty for the platform colour"
            autoCapitalize="none"
            value={color}
            onChangeText={setColor}
            error={errors.color}
            right={<View style={{ width: 20, height: 20, borderRadius: 10, marginTop: 18, marginRight: 12, backgroundColor: preview ?? 'transparent' }} />}
          />
          <TextField
            label="Logo URL"
            placeholder="https://…"
            helperText="A square image works best"
            keyboardType="url"
            autoCapitalize="none"
            value={logo}
            onChangeText={setLogo}
            error={errors.logo}
          />
          <TextField label="Contact phone" keyboardType="phone-pad" value={phone} onChangeText={setPhone} />
          <TextField label="Address" multiline minLines={2} value={address} onChangeText={setAddress} />
          <SelectField
            label="Recall after"
            helperText="Patients with no visit since, and nothing booked, show as due for recall"
            value={recallMonths}
            options={recallOptions.map((m) => ({ value: m, label: `${m} months` }))}
            onChange={setRecallMonths}
          />
        </View>
      </Dialog.ScrollArea>
      <Dialog.Actions>
        <Button onPress={() => close()}>Cancel</Button>
        <Button mode="contained" onPress={save}>
          Save
        </Button>
      </Dialog.Actions>
    </>
  );
}

// ── Join code ───────────────────────────────────────────────────────────────

function JoinCodeCard({ clinic }: { clinic: Clinic }) {
  const { colors } = useAppTheme();
  const qc = useQueryClient();
  const overlay = useOverlay();
  const repo = useRepository();
  const code = clinic.joinCode;
  const refresh = () => void qc.invalidateQueries({ queryKey: ['visibleClinics'] });

  const rotate = async () => {
    const hadCode = code != null;
    if (hadCode) {
      const ok = await overlay.confirm({
        title: 'Issue a new code?',
        message: 'The current code stops working immediately. Patients who have already joined are not affected.',
        confirmLabel: 'New code',
      });
      if (!ok) return;
    }
    try {
      const fresh = await repo.rotateJoinCode(clinic.id);
      refresh();
      overlay.snack(hadCode ? `New code: ${fresh}` : `Patients can join with ${fresh}`);
    } catch (e) {
      overlay.snack(describeError(e));
    }
  };

  const turnOff = async () => {
    const ok = await overlay.confirm({
      title: 'Turn off joining by code?',
      message: `Patients will not be able to join ${clinic.name} with a code until you turn it back on. Patients who have already joined are not affected.`,
      confirmLabel: 'Turn off',
      destructive: true,
    });
    if (!ok) return;
    try {
      await repo.updateClinic(clinic.id, { join_code: null });
      refresh();
      overlay.snack('Joining by code is off');
    } catch (e) {
      overlay.snack(describeError(e));
    }
  };

  return (
    <AppCard padding={16}>
      <Text style={{ color: colors.onSurfaceVariant }}>
        {code == null
          ? `Patients cannot join ${clinic.name} on their own right now. Staff can still register walk-ins.`
          : `Patients enter this code in the patient app to join ${clinic.name}.`}
      </Text>
      {code != null && (
        <View style={{ flexDirection: 'row', alignItems: 'center', marginTop: 12 }}>
          <Text selectable variant="headlineMedium" style={{ flex: 1, fontWeight: '700', letterSpacing: 6, color: colors.primary }}>
            {code}
          </Text>
          <BarAction
            icon="content-copy"
            label="Copy code"
            onPress={async () => overlay.snack((await copyText(code)) ? 'Code copied' : 'Could not copy the code')}
          />
        </View>
      )}
      <Wrap align="center" style={{ marginTop: 12 }}>
        {code != null ? (
          <>
            <Button mode="outlined" icon="refresh" onPress={() => void rotate()}>
              New code
            </Button>
            <Button onPress={() => void turnOff()}>Turn off</Button>
          </>
        ) : (
          <Button mode="contained" icon="lock-open" onPress={() => void rotate()}>
            Turn on
          </Button>
        )}
      </Wrap>
    </AppCard>
  );
}

// ── Staff ───────────────────────────────────────────────────────────────────

type Invite = { email: string; role: AppRole; branchLocked: boolean };

function StaffSection() {
  const { colors } = useAppTheme();
  const qc = useQueryClient();
  const overlay = useOverlay();
  const repo = useRepository();
  const clinicId = useCurrentClinicId();
  const clinic = useCurrentClinic().value ?? null;
  const staffAsync = useStaff();
  const me = useCurrentUserId();
  // A branch admin manages doctors and assistants, never admins.
  const isFullAdmin = useIsFullAdmin();
  const refresh = () => {
    void qc.invalidateQueries({ queryKey: ['staff'] });
    // The admin may have just changed their OWN role.
    void qc.invalidateQueries({ queryKey: ['memberships'] });
  };

  const invite = async (existing?: ClinicMembership) => {
    const result = await overlay.showDialog<Invite>((close) => <InviteDialog existing={existing ?? null} canGrantAdmin={isFullAdmin} close={close} />);
    if (result == null || clinicId == null) return;
    const roleName = result.branchLocked ? 'branch admin' : roleDisplayName(result.role).toLowerCase();
    try {
      await repo.inviteStaff({ clinicId, email: result.email, role: result.role, branchLocked: result.branchLocked });
      refresh();
      overlay.snack(existing == null ? `${result.email} added as ${roleName}` : `Role updated to ${roleName}`);
    } catch (e) {
      overlay.snack(describeError(e));
    }
  };

  const remove = async (member: ClinicMembership) => {
    const name = member.fullName ?? member.email ?? 'this person';
    const ok = await overlay.confirm({
      title: `Remove ${name}?`,
      message: `They lose access to ${clinic?.name ?? 'this clinic'} straight away. Appointments and notes they worked on stay.`,
      confirmLabel: 'Remove',
      destructive: true,
    });
    if (!ok) return;
    try {
      await repo.removeStaff({ clinicId: member.clinicId, profileId: member.profileId });
      refresh();
      overlay.snack(`${name} removed`);
    } catch (e) {
      overlay.snack(describeError(e));
    }
  };

  return (
    <View>
      <SectionTitle
        action={
          <Button icon="person-add-alt" onPress={() => void invite()}>
            Add
          </Button>
        }
      >
        Staff
      </SectionTitle>
      <AsyncView value={staffAsync} padded onRetry={() => void qc.invalidateQueries({ queryKey: ['staff'] })}>
        {(staff) => (
          <View style={{ gap: 8 }}>
            {staff.map((member) => {
              const label = member.fullName ?? member.email ?? '';
              const editable = isFullAdmin || member.role !== 'admin';
              return (
                <AppCard key={member.profileId}>
                  <ListTile
                    onPress={editable ? () => void invite(member) : undefined}
                    leading={<Avatar label={label.trim() === '' ? '?' : initialsOf(label)} />}
                    title={member.fullName ?? member.email ?? 'Unknown'}
                    subtitle={[member.roleLabel, ...(member.email != null ? [member.email] : [])].join(' · ')}
                    trailing={
                      member.profileId === me ? (
                        <Text style={{ color: colors.onSurfaceVariant }}>You</Text>
                      ) : !editable ? undefined : (
                        <BarAction icon="person-remove" label="Remove from clinic" onPress={() => void remove(member)} />
                      )
                    }
                  />
                </AppCard>
              );
            })}
          </View>
        )}
      </AsyncView>
    </View>
  );
}

/// Adds someone, or changes an existing member's role.
function InviteDialog({
  existing,
  canGrantAdmin,
  close,
}: {
  existing: ClinicMembership | null;
  /// False for a branch admin, who may not hand out either kind of admin.
  canGrantAdmin: boolean;
  close: (v?: Invite) => void;
}) {
  const { colors } = useAppTheme();
  const isEdit = existing != null;
  const [email, setEmail] = useState(existing?.email ?? '');
  const [role, setRole] = useState<AppRole>(existing?.role ?? 'assistant');
  const [branchLocked, setBranchLocked] = useState(existing?.branchLocked ?? false);
  const [error, setError] = useState<string | null>(null);
  return (
    <>
      <Dialog.Title>{isEdit ? 'Change role' : 'Add staff'}</Dialog.Title>
      <Dialog.Content>
        <TextField
          label="Email"
          value={email}
          onChangeText={setEmail}
          disabled={isEdit}
          autoFocus={!isEdit}
          autoCapitalize="none"
          autoComplete="email"
          keyboardType="email-address"
          error={error}
        />
        <SegmentedButtons
          style={{ marginTop: 16 }}
          value={role}
          onValueChange={(v) => setRole(v as AppRole)}
          buttons={[
            { value: 'doctor', label: 'Doctor' },
            { value: 'assistant', label: 'Assistant' },
            ...(canGrantAdmin ? [{ value: 'admin', label: 'Admin' }] : []),
          ]}
        />
        {role === 'admin' && (
          <View style={{ marginTop: 8 }}>
            <SwitchRow
              title="Branch admin"
              subtitle="Runs this clinic only. Cannot add or change admins, and cannot be an admin at any other clinic."
              value={branchLocked}
              onChange={setBranchLocked}
            />
          </View>
        )}
        {!isEdit && (
          <Text style={{ marginTop: 16, fontSize: 12, color: colors.onSurfaceVariant }}>
            They need an account first: ask them to create one in any of the apps with this email, then add them here. Doctors and assistants can
            also join with a staff code.
          </Text>
        )}
      </Dialog.Content>
      <Dialog.Actions>
        <Button onPress={() => close()}>Cancel</Button>
        <Button
          mode="contained"
          onPress={() => {
            if (!email.includes('@')) {
              setError('Enter a valid email');
              return;
            }
            close({ email: email.trim(), role, branchLocked: role === 'admin' && branchLocked });
          }}
        >
          {isEdit ? 'Save' : 'Add'}
        </Button>
      </Dialog.Actions>
    </>
  );
}

// ── Bookings ────────────────────────────────────────────────────────────────

/// Where what patients can book is set up: who, what, and when not.
function BookingsCard() {
  const nav = useClinicNav();
  const doctors = useRoster().value;
  const services = useCatalogue().value;
  const timeOff = useTimeOff().value;
  const count = (list: readonly unknown[] | undefined, one: string, many: string) =>
    list == null ? undefined : `${list.length} ${list.length === 1 ? one : many}`;
  const tiles: [IconName, string, string | undefined, string][] = [
    ['badge', 'Doctors & hours', count(doctors, 'doctor', 'doctors'), '/settings/doctors'],
    ['medical-services', 'Services & prices', count(services, 'service', 'services'), '/settings/services'],
    ['event-busy', 'Closures & leave', timeOff == null ? undefined : timeOff.length === 0 ? 'None coming up' : `${timeOff.length} coming up`, '/settings/closures'],
  ];
  return (
    <AppCard>
      {tiles.map(([icon, title, subtitle, path], i) => (
        <Fragment key={path}>
          {i > 0 && <Divider style={{ marginLeft: 56 }} />}
          <ListTile leading={<Icon name={icon} />} title={title} subtitle={subtitle} trailing={<Icon name="chevron-right" />} onPress={() => nav.push(path)} />
        </Fragment>
      ))}
    </AppCard>
  );
}
