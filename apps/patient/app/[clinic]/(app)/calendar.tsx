import { AppointmentCalendarScreen, useClinicNav } from '@health/shared';

export default function Calendar() {
  const nav = useClinicNav();
  return (
    <AppointmentCalendarScreen
      scope="patient"
      onOpenAppointment={(a) => nav.push(`/appointments/${a.id}`)}
      onBookAsPatient={() => nav.push('/book')}
    />
  );
}
