import { PatientHistoryScreen, useClinicNav } from '@health/shared';
import { useLocalSearchParams } from 'expo-router';

export default function Patient() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const nav = useClinicNav();
  return <PatientHistoryScreen key={id} patientId={id} onOpenAppointment={(a) => nav.open(`/appointments/${a.id}`)} />;
}
