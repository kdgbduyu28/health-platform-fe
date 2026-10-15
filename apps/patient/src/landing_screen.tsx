import {
  AppCard,
  AsyncView,
  ClinicMark,
  type Clinic,
  type ClinicPage,
  DoctorAvatar,
  Icon,
  type IconName,
  ListTile,
  formatWeekdays,
  useAppTheme,
  useClinicNav,
  useClinicPage,
  useCurrentClinic,
  useIsSignedIn,
  useRepository,
  useRouteClinicSlug,
} from '@health/shared';
import { useQueryClient } from '@tanstack/react-query';
import { Fragment, type ReactNode } from 'react';
import { ScrollView, View } from 'react-native';
import { Button, Divider, Text } from 'react-native-paper';

/// `/:clinic` — the clinic's public page, for anyone with the link.
///
/// Everything here comes from `clinic_by_slug`, the one thing an anonymous
/// visitor may read: branding, contact details, services and doctors. What
/// it offers next depends on who is looking — a visitor can sign in or
/// create an account, a patient of the clinic can book, and a signed-in
/// account that has not joined yet is asked for the clinic's code. Joining
/// still takes that code: the page shows the clinic, it does not admit.
export function ClinicLandingScreen() {
  const slug = useRouteClinicSlug();
  const page = useClinicPage(slug);
  const qc = useQueryClient();
  const { colors } = useAppTheme();
  return (
    <View style={{ flex: 1, backgroundColor: colors.surface }}>
      <AsyncView value={page} onRetry={() => void qc.invalidateQueries({ queryKey: ['clinicPage', slug] })}>
        {/* Null is an unknown clinic, which the router has already sent to
            /not-found; this frame is on its way out. */}
        {(data) => (data == null ? null : <Landing page={data} />)}
      </AsyncView>
    </View>
  );
}

function Landing({ page }: { page: ClinicPage }) {
  const { colors } = useAppTheme();
  const clinic = page.clinic;
  return (
    <ScrollView contentContainerStyle={{ paddingHorizontal: 16, paddingTop: 16, paddingBottom: 40 }}>
      <View style={{ width: '100%', maxWidth: 720, alignSelf: 'center' }}>
        <Hero clinic={clinic} />
        <View style={{ height: 16 }} />
        <Actions />
        {page.services.length > 0 && (
          <>
            <SectionTitle text="Services" count={page.services.length} />
            <AppCard>
              {page.services.map((s, i) => (
                <Fragment key={s.id}>
                  {i > 0 && <Divider style={{ marginLeft: 16 }} />}
                  <ListTile
                    leading={<Icon name="medical-services" color={colors.primary} />}
                    title={s.name}
                    trailing={
                      <Text style={{ color: colors.onSurfaceVariant }}>
                        {[`${s.durationMinutes} min`, ...(s.priceLabel != null ? [s.priceLabel] : [])].join(' · ')}
                      </Text>
                    }
                  />
                </Fragment>
              ))}
            </AppCard>
          </>
        )}
        {page.doctors.length > 0 && (
          <>
            <SectionTitle text="Our doctors" count={page.doctors.length} />
            <AppCard>
              {page.doctors.map((d, i) => (
                <Fragment key={d.id}>
                  {i > 0 && <Divider style={{ marginLeft: 72 }} />}
                  <ListTile
                    leading={<DoctorAvatar doctor={d} radius={20} />}
                    title={d.name}
                    subtitle={[
                      ...(d.specialty !== '' ? [d.specialty] : []),
                      ...(d.availableWeekdays.length > 0 ? [formatWeekdays(d.availableWeekdays)] : []),
                    ].join(' · ')}
                  />
                </Fragment>
              ))}
            </AppCard>
          </>
        )}
        <Text variant="bodySmall" style={{ marginTop: 32, textAlign: 'center', color: colors.onSurfaceVariant }}>
          Powered by the {clinic.name} patient app
        </Text>
      </View>
    </ScrollView>
  );
}

function Hero({ clinic }: { clinic: Clinic }) {
  const { colors } = useAppTheme();
  return (
    <View
      style={{
        paddingHorizontal: 24,
        paddingTop: 32,
        paddingBottom: 24,
        borderRadius: 28,
        backgroundColor: colors.primaryContainer,
        alignItems: 'center',
      }}
    >
      <ClinicMark clinic={clinic} size={88} />
      <Text variant="headlineMedium" style={{ marginTop: 16, textAlign: 'center', fontWeight: '700', color: colors.onPrimaryContainer }}>
        {clinic.name}
      </Text>
      <View
        style={{
          marginTop: 8,
          flexDirection: 'row',
          alignItems: 'center',
          gap: 6,
          paddingHorizontal: 10,
          paddingVertical: 4,
          borderRadius: 8,
          backgroundColor: colors.surface,
        }}
      >
        <Icon name={clinic.icon} size={16} color={colors.primary} />
        <Text variant="labelLarge">{clinic.typeName}</Text>
      </View>
      {(clinic.address != null || clinic.contactPhone != null) && (
        <View style={{ marginTop: 16, alignItems: 'center' }}>
          {clinic.address != null && <ContactLine icon="place" text={clinic.address} />}
          {clinic.contactPhone != null && <ContactLine icon="call" text={clinic.contactPhone} />}
        </View>
      )}
    </View>
  );
}

function ContactLine({ icon, text }: { icon: IconName; text: string }) {
  const { colors } = useAppTheme();
  const color = colors.onPrimaryContainer;
  return (
    <View style={{ flexDirection: 'row', alignItems: 'center', gap: 6, paddingVertical: 2, maxWidth: '100%' }}>
      <Icon name={icon} size={16} color={color} />
      <Text selectable style={{ color, flexShrink: 1 }}>
        {text}
      </Text>
    </View>
  );
}

/// What this visitor can do next.
function Actions() {
  const { colors } = useAppTheme();
  const signedIn = useIsSignedIn();
  const isPatientHere = useCurrentClinic().value != null;
  const nav = useClinicNav();
  const repo = useRepository();

  let buttons: ReactNode;
  let note: string | null = null;
  if (!signedIn) {
    buttons = (
      <>
        {/* The router asks them to sign in first, then brings them back. */}
        <Button mode="contained" icon="event-available" onPress={() => nav.go('/book')}>
          Book an appointment
        </Button>
        <Button mode="outlined" onPress={() => nav.go('/sign-in')}>
          Sign in
        </Button>
        <Button onPress={() => nav.go('/sign-in?mode=sign-up')}>Create account</Button>
      </>
    );
    note = 'New patient? Create an account, then enter the code the clinic gives you.';
  } else if (isPatientHere) {
    buttons = (
      <>
        <Button mode="contained" icon="event-available" onPress={() => nav.go('/book')}>
          Book an appointment
        </Button>
        <Button mode="outlined" icon="calendar-today" onPress={() => nav.go('/home')}>
          My appointments
        </Button>
      </>
    );
  } else {
    buttons = (
      <>
        <Button mode="contained" icon="vpn-key" onPress={() => nav.go('/join')}>
          Join with clinic code
        </Button>
        <Button onPress={() => void repo.signOut()}>Sign out</Button>
      </>
    );
    note = 'You are signed in but have not joined this clinic yet. Ask the clinic for its code.';
  }

  return (
    <View style={{ alignItems: 'center' }}>
      <View style={{ flexDirection: 'row', flexWrap: 'wrap', justifyContent: 'center', gap: 8 }}>{buttons}</View>
      {note != null && <Text style={{ marginTop: 12, textAlign: 'center', fontSize: 13, color: colors.onSurfaceVariant }}>{note}</Text>}
    </View>
  );
}

function SectionTitle({ text, count }: { text: string; count: number }) {
  return (
    <Text variant="titleMedium" style={{ marginTop: 32, marginBottom: 8, paddingHorizontal: 4, fontWeight: '700' }}>
      {text} ({count})
    </Text>
  );
}
