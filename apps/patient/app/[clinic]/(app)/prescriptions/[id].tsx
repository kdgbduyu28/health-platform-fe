import { useLocalSearchParams } from 'expo-router';

import { PrescriptionScreen } from '../../../../src/my_prescriptions_screen';

export default function Prescription() {
  const { id } = useLocalSearchParams<{ id: string }>();
  return <PrescriptionScreen key={id} id={id} />;
}
