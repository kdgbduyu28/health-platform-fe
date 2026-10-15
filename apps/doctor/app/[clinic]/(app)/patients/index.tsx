import { PatientDirectoryScreen, useClinicNav } from '@health/shared';

export default function Patients() {
  const nav = useClinicNav();
  return <PatientDirectoryScreen onOpenPatient={(p) => nav.push(`/patients/${p.id}`)} />;
}
