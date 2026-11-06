import {
  AsyncView,
  AttachmentGrid,
  ContentWidth,
  EmptyState,
  Page,
  invalidateAttachments,
  useMyAttachments,
  useOpenAttachment,
} from '@health/shared';
import { useQueryClient } from '@tanstack/react-query';

/// The x-rays, photos and documents the clinic has shared with the signed-in
/// patient. The rest of their chart's files stay with the clinicians.
export function MyFilesScreen() {
  const qc = useQueryClient();
  const async = useMyAttachments();
  const open = useOpenAttachment(false);
  return (
    <Page title="X-rays & photos" back="/profile" maxWidth={ContentWidth.list}>
      <AsyncView value={async} padded onRetry={() => void invalidateAttachments(qc)}>
        {(list) =>
          list.length === 0 ? (
            <EmptyState icon="medical-information" title="Nothing shared yet" message="Your doctor can share x-rays and photos of your treatment here." />
          ) : (
            <AttachmentGrid list={list} onOpen={open} />
          )
        }
      </AsyncView>
    </Page>
  );
}
