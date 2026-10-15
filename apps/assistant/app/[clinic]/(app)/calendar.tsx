import { AppointmentCalendarScreen, useClinicNav } from '@health/shared';

/// The front desk has no appointment page: a visit opens in a sheet, and
/// tapping empty time books it.
export default function Calendar() {
  const nav = useClinicNav();
  return <AppointmentCalendarScreen scope="clinic" canBook onOpenPatient={(id) => nav.push(`/patients/${id}`)} />;
}
