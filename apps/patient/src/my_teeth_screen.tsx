import { AsyncView, MyDentalChartScreen, Page, useMyPatient } from '@health/shared';
import { useQueryClient } from '@tanstack/react-query';
import { Text } from 'react-native-paper';

/// The signed-in patient's chart at this clinic, once it has loaded.
export function MyTeethScreen() {
  const qc = useQueryClient();
  const me = useMyPatient();
  if (me.hasValue && me.value != null) return <MyDentalChartScreen patient={me.value} />;
  return (
    <Page title="My teeth" back="/home">
      <AsyncView value={me} padded onRetry={() => void qc.invalidateQueries({ queryKey: ['myPatients'] })}>
        {() => <Text style={{ textAlign: 'center', padding: 32 }}>No chart at this clinic.</Text>}
      </AsyncView>
    </Page>
  );
}
