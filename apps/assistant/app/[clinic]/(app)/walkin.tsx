import { useLocalSearchParams } from 'expo-router';

import { WalkInBookingScreen } from '../../../src/walkin_booking_screen';

/// `?patient=` preselects a chart, when booking from a patient's page.
export default function WalkIn() {
  const { patient } = useLocalSearchParams<{ patient?: string }>();
  return <WalkInBookingScreen initialPatientId={patient ?? null} />;
}
