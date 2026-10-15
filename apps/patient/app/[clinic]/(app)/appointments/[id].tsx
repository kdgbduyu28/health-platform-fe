import { useLocalSearchParams } from 'expo-router';

import { AppointmentDetailScreen } from '../../../../src/appointment_detail_screen';

export default function Appointment() {
  const { id } = useLocalSearchParams<{ id: string }>();
  return <AppointmentDetailScreen key={id} appointmentId={id} />;
}
