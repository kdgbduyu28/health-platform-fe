import { AppointmentCalendarScreen, useClinicNav } from '@health/shared';

export default function Calendar() {
  const nav = useClinicNav();
  return <AppointmentCalendarScreen scope="doctor" onOpenAppointment={(a) => nav.push(`/appointments/${a.id}`)} />;
}
