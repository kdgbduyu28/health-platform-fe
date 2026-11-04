import {
  AsyncView,
  ContentWidth,
  EmptyState,
  Icon,
  Page,
  PrescriptionView,
  invalidatePrescriptions,
  useAppTheme,
  useMyPatient,
  useMyPrescriptions,
  usePrescription,
  usePrintPrescription,
  useVisitPrescriptions,
} from '@health/shared';
import { useQueryClient } from '@tanstack/react-query';
import { View } from 'react-native';
import { Text } from 'react-native-paper';

/// The signed-in patient's prescriptions at this clinic, newest first. A
/// voided one is not shown: the database keeps it from the patient.
export function MyPrescriptionsScreen() {
  const qc = useQueryClient();
  const async = useMyPrescriptions();
  const chart = useMyPatient().value ?? null;
  const print = usePrintPrescription();
  return (
    <Page title="Prescriptions" back="/profile" maxWidth={ContentWidth.list} padding={12}>
      <AsyncView value={async} padded onRetry={() => void invalidatePrescriptions(qc)}>
        {(list) =>
          list.length === 0 ? (
            <EmptyState icon="medication" title="No prescriptions yet" message="What your doctor prescribes shows here, ready to print for the pharmacy." />
          ) : (
            <View style={{ gap: 8 }}>
              {list.map((rx) => (
                <PrescriptionView key={rx.id} rx={rx} onPrint={chart == null ? undefined : () => print(chart, rx)} />
              ))}
            </View>
          )
        }
      </AsyncView>
    </Page>
  );
}

/// One prescription, where a notification links to.
export function PrescriptionScreen({ id }: { id: string }) {
  const qc = useQueryClient();
  const async = usePrescription(id);
  const chart = useMyPatient().value ?? null;
  const print = usePrintPrescription();
  return (
    <Page title="Prescription" back="/prescriptions" maxWidth={ContentWidth.list} padding={12}>
      <AsyncView value={async} padded onRetry={() => void invalidatePrescriptions(qc)}>
        {(rx) =>
          rx == null ? (
            <EmptyState icon="medication" title="Not found" message="It may have been withdrawn by the clinic." />
          ) : (
            <PrescriptionView rx={rx} onPrint={chart == null ? undefined : () => print(chart, rx)} />
          )
        }
      </AsyncView>
    </Page>
  );
}

/// What was prescribed at one visit, on its details page. Nothing when there
/// is none.
export function VisitPrescriptionsCard({ appointmentId }: { appointmentId: string }) {
  const { colors } = useAppTheme();
  const list = useVisitPrescriptions(appointmentId).value ?? [];
  const chart = useMyPatient().value ?? null;
  const print = usePrintPrescription();
  if (list.length === 0) return null;
  return (
    <View style={{ gap: 8 }}>
      <View style={{ flexDirection: 'row', alignItems: 'center', gap: 6 }}>
        <Icon name="medication" size={16} color={colors.primary} />
        <Text style={{ fontWeight: '600', color: colors.onSurfaceVariant }}>{list.length === 1 ? 'Prescription' : 'Prescriptions'}</Text>
      </View>
      {list.map((rx) => (
        <PrescriptionView key={rx.id} rx={rx} onPrint={chart == null ? undefined : () => print(chart, rx)} />
      ))}
    </View>
  );
}
