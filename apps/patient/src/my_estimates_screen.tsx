import {
  AppCard,
  AsyncView,
  ContentWidth,
  EmptyState,
  EstimateStatusChip,
  EstimateView,
  ListTile,
  Page,
  describeError,
  formatPeso,
  invalidateEstimates,
  useClinicNav,
  useEstimate,
  useMyEstimates,
  useOverlay,
  useRepository,
} from '@health/shared';
import { useQueryClient } from '@tanstack/react-query';
import { format } from 'date-fns';
import { useState } from 'react';
import { View } from 'react-native';
import { Button, Text } from 'react-native-paper';

/// What the clinic has quoted the signed-in patient, newest first. Drafts
/// and voided ones never reach a patient.
export function MyEstimatesScreen() {
  const qc = useQueryClient();
  const nav = useClinicNav();
  const async = useMyEstimates();
  return (
    <Page title="Treatment estimates" back="/profile" maxWidth={ContentWidth.list} padding={12}>
      <AsyncView value={async} padded onRetry={() => void invalidateEstimates(qc)}>
        {(list) =>
          list.length === 0 ? (
            <EmptyState icon="sell" title="No estimates" message="When the clinic quotes a treatment, it shows here for you to accept or decline." />
          ) : (
            <View style={{ gap: 8 }}>
              {list.map((e) => (
                <AppCard key={e.id}>
                  <ListTile
                    onPress={() => nav.push(`/estimates/${e.id}`)}
                    title={<Text style={{ fontWeight: '600' }}>{e.title ?? 'Treatment estimate'}</Text>}
                    subtitle={<EstimateStatusChip estimate={e} />}
                    trailing={
                      <View style={{ alignItems: 'flex-end' }}>
                        <Text style={{ fontWeight: '700' }}>{formatPeso(e.total)}</Text>
                        <Text style={{ fontSize: 12 }}>{format(e.sentAt ?? e.createdAt, 'MMM d')}</Text>
                      </View>
                    }
                  />
                </AppCard>
              ))}
            </View>
          )
        }
      </AsyncView>
    </Page>
  );
}

/// One estimate, where the notification links to, with the patient's yes or
/// no while it is open.
export function EstimateScreen({ id }: { id: string }) {
  const qc = useQueryClient();
  const overlay = useOverlay();
  const repo = useRepository();
  const async = useEstimate(id);
  const [busy, setBusy] = useState(false);

  const decide = async (accept: boolean) => {
    const ok = await overlay.confirm({
      title: accept ? 'Accept this estimate?' : 'Decline this estimate?',
      message: accept
        ? 'The clinic will plan your treatment at these prices. You pay as the work is done, not now.'
        : 'The clinic will know you do not want to go ahead for now. You can ask for a new estimate any time.',
      confirmLabel: accept ? 'Accept' : 'Decline',
    });
    if (!ok) return;
    setBusy(true);
    try {
      await repo.decideEstimate(id, accept);
      overlay.snack(accept ? 'Accepted. The clinic has been told.' : 'Declined. The clinic has been told.');
    } catch (e) {
      overlay.snack(describeError(e));
    } finally {
      setBusy(false);
      void invalidateEstimates(qc);
    }
  };

  return (
    <Page title="Treatment estimate" back="/estimates" maxWidth={ContentWidth.list}>
      <AsyncView value={async} padded onRetry={() => void invalidateEstimates(qc)}>
        {(e) =>
          e == null ? (
            <EmptyState icon="sell" title="Not found" message="The clinic may have withdrawn it." />
          ) : (
            <View style={{ gap: 16 }}>
              <EstimateView estimate={e} />
              {e.canDecide() && (
                <View style={{ flexDirection: 'row', gap: 8 }}>
                  <Button mode="contained" icon="check" style={{ flex: 1 }} disabled={busy} onPress={() => void decide(true)}>
                    Accept
                  </Button>
                  <Button mode="outlined" style={{ flex: 1 }} disabled={busy} onPress={() => void decide(false)}>
                    Decline
                  </Button>
                </View>
              )}
              {e.status === 'sent' && e.expired() && (
                <Text style={{ textAlign: 'center' }}>This estimate has expired. Ask the clinic for a new one.</Text>
              )}
            </View>
          )
        }
      </AsyncView>
    </Page>
  );
}
