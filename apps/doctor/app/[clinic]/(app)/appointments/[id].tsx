import { useLocalSearchParams } from 'expo-router';

import { DoctorAppointmentDetailScreen } from '../../../../src/appointment_detail_screen';

export default function Appointment() {
  const { id } = useLocalSearchParams<{ id: string }>();
  return <DoctorAppointmentDetailScreen key={id} appointmentId={id} />;
}
