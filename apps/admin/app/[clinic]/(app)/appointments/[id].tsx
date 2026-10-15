import { useLocalSearchParams } from 'expo-router';

import { AdminAppointmentDetailScreen } from '../../../../src/appointment_detail_screen';

export default function Appointment() {
  const { id } = useLocalSearchParams<{ id: string }>();
  return <AdminAppointmentDetailScreen key={id} appointmentId={id} />;
}
