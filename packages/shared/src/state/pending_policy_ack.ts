import { privacyPolicyVersion, termsVersion } from '../legal/documents';
import { preferences } from './preferences';

/// How long a tick on the create-account form waits for Google to send the
/// browser back. Past this it is somebody else's, later, and is dropped.
const pendingTtlMs = 15 * 60 * 1000;

/// Remembers, just before leaving for Google, that the create-account form's
/// Terms and Privacy Policy box was ticked.
export function rememberPolicyAckForGoogle(): void {
  preferences.setPendingPolicyAck(JSON.stringify({ privacy: privacyPolicyVersion, terms: termsVersion, at: Date.now() }));
}

export function forgetPolicyAckForGoogle(): void {
  preferences.setPendingPolicyAck(null);
}

/// Records the tick left by [rememberPolicyAckForGoogle], if it is recent.
export async function recordPendingPolicyAck(acknowledge: (document: 'privacy' | 'terms', version: string) => Promise<void>) {
  const raw = preferences.pendingPolicyAck;
  if (raw == null) return;
  let pending: { privacy?: unknown; terms?: unknown; at?: unknown };
  try {
    pending = JSON.parse(raw);
  } catch {
    forgetPolicyAckForGoogle();
    return;
  }
  if (typeof pending.at !== 'number' || Date.now() - pending.at > pendingTtlMs) {
    forgetPolicyAckForGoogle();
    return;
  }
  if (typeof pending.privacy === 'string') await acknowledge('privacy', pending.privacy);
  if (typeof pending.terms === 'string') await acknowledge('terms', pending.terms);
  forgetPolicyAckForGoogle();
}
