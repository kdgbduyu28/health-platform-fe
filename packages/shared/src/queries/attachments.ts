import { type QueryClient, useQuery } from '@tanstack/react-query';

import type { ChartAttachment } from '../models/attachment';
import { useRepository } from '../state/platform';
import { type AsyncValue, fromQuery } from './async_value';
import { useMyPatient } from './catalog';

/// One chart's files, newest first. Clinicians see all; the patient what was
/// shared with them.
export function usePatientAttachments(patientId: string): AsyncValue<ChartAttachment[]> {
  const repo = useRepository();
  return fromQuery(useQuery({ queryKey: ['attachments', patientId], queryFn: () => repo.fetchPatientAttachments(patientId) }));
}

/// The signed-in patient's shared files at the current clinic.
export function useMyAttachments(): AsyncValue<ChartAttachment[]> {
  const repo = useRepository();
  const chart = useMyPatient().value;
  return fromQuery(
    useQuery({
      queryKey: ['attachments', chart?.id ?? null],
      queryFn: () => (chart == null ? [] : repo.fetchPatientAttachments(chart.id)),
    }),
  );
}

/// A signed link to the file, renewed before its hour runs out.
export function useAttachmentUrl(a: ChartAttachment): AsyncValue<string> {
  const repo = useRepository();
  return fromQuery(
    useQuery({
      queryKey: ['attachmentUrl', a.storagePath],
      queryFn: () => repo.attachmentUrl(a.storagePath),
      staleTime: 50 * 60 * 1000,
      refetchInterval: 50 * 60 * 1000,
    }),
  );
}

export function invalidateAttachments(qc: QueryClient): Promise<void> {
  return qc.invalidateQueries({ queryKey: ['attachments'] });
}
