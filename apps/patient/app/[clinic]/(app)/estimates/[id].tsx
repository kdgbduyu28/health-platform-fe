import { useLocalSearchParams } from 'expo-router';

import { EstimateScreen } from '../../../../src/my_estimates_screen';

export default function Estimate() {
  const { id } = useLocalSearchParams<{ id: string }>();
  return <EstimateScreen key={id} id={id} />;
}
