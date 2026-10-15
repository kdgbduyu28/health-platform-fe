import { PatientHistoryScreen, useClinicNav } from '@health/shared';
import { useLocalSearchParams } from 'expo-router';

export default function Patient() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const nav = useClinicNav();
  return (
    <PatientHistoryScreen
      key={id}
      patientId={id}
      onBook={() => nav.go(`/walkin?patient=${id}`)}
      onOpenInvoice={(bill) => nav.push(`/billing/${bill}`)}
      canRecordVisits
    />
  );
}
