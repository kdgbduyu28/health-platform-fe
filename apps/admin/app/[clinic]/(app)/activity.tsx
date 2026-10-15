import { AuditLogScreen, useClinicNav } from '@health/shared';

export default function Activity() {
  const nav = useClinicNav();
  return <AuditLogScreen onOpenPatient={(id) => nav.push(`/patients/${id}`)} />;
}
