import type { AppRole } from '../models/app_role';

/// The demo accounts made by health-platform-be's
/// supabase/dev/create_demo_users.sql, offered on the sign-in screen while
/// the platform is a showcase. Keep the two in step.
///
/// These are public on purpose: anyone who opens the sign-in screen sees
/// them. Before a real clinic's data goes in, build with
/// EXPO_PUBLIC_DEMO_LOGINS=off (or delete this file and its button), and
/// remove the accounts themselves.
export type DemoLogin = {
  email: string;
  label: string;
  detail: string;
  app: AppRole;
};

/// The one password the script gives every demo account.
export const demoPassword = 'demo1234';

export const demoLogins: readonly DemoLogin[] = [
  { email: 'juan@email.com', label: 'Juan dela Cruz', detail: 'Patient with charts at 3 clinics', app: 'patient' },
  { email: 'santos@clinic.ph', label: 'Dr Maria Santos', detail: 'Doctor at D-Touch', app: 'doctor' },
  { email: 'frontdesk@clinic.ph', label: 'Front desk', detail: 'Assistant at D-Touch', app: 'assistant' },
  { email: 'admin@clinic.ph', label: 'Clinic admin', detail: 'Admin at D-Touch, ClearVision, Little Stars', app: 'admin' },
  { email: 'admin@brightsmile.ph', label: 'BrightSmile admin', detail: 'Admin at BrightSmile only', app: 'admin' },
];

/// Whether this build shows the demo logins. On unless built with
/// EXPO_PUBLIC_DEMO_LOGINS=off. Written out in full so Expo inlines it.
export const demoLoginsEnabled = process.env.EXPO_PUBLIC_DEMO_LOGINS !== 'off';

/// The demo accounts meant for [app]. The others would sign in and land on
/// "no access", so they are left out.
export function demoLoginsFor(app: AppRole): DemoLogin[] {
  return demoLogins.filter((d) => d.app === app);
}
