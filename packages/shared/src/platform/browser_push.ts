/// What a browser hands over when it subscribes to Web Push: where to send,
/// and the keys to encrypt for it. The send-push Edge Function needs all
/// three.
export type PushKeys = { endpoint: string; p256dh: string; auth: string };

/// This browser's Web Push, behind one small interface: the web build uses
/// the Push API; tests get a browser without it.
///
/// Pushes are shown by `public/push_sw.js`, a service worker registered under
/// `./push/` so it controls no page and never gets in the app's way.
export interface BrowserPush {
  /// The Push API and notifications exist here. False on iPhone Safari unless
  /// the site was added to the home screen.
  readonly supported: boolean;

  /// An iPhone or iPad where adding the site to the home screen would turn
  /// push on.
  readonly needsHomeScreenInstall: boolean;

  /// `granted`, `denied` or `default` (not asked yet).
  readonly permission: string;

  readonly userAgent: string;

  /// The subscription this browser already holds, if any.
  current(): Promise<PushKeys | null>;

  /// Asks for permission if need be, then subscribes with the platform's
  /// VAPID public key. Null if the person said no.
  subscribe(vapidPublicKey: string): Promise<PushKeys | null>;

  /// Drops this browser's subscription. Returns its endpoint, if it had one.
  unsubscribe(): Promise<string | null>;

  /// Calls [open] with the link of a notification tapped while the app is
  /// already open, so it can navigate rather than open a second tab.
  onNotificationOpened(open: (link: string) => void): () => void;
}

const worker = '/push_sw.js';
const scope = '/push/';

class WebPush implements BrowserPush {
  get supported(): boolean {
    return (
      typeof window !== 'undefined' &&
      'PushManager' in window &&
      'Notification' in window &&
      'serviceWorker' in navigator
    );
  }

  get needsHomeScreenInstall(): boolean {
    if (this.supported) return false;
    const ua = this.userAgent;
    return ua.includes('iPhone') || ua.includes('iPad');
  }

  get permission(): string {
    return typeof window !== 'undefined' && 'Notification' in window ? Notification.permission : 'denied';
  }

  get userAgent(): string {
    return typeof navigator === 'undefined' ? '' : navigator.userAgent;
  }

  private existing(): Promise<ServiceWorkerRegistration | undefined> {
    return navigator.serviceWorker.getRegistration(scope);
  }

  /// Registers push_sw.js and waits for it to be active: a push subscription
  /// needs an active worker, and `serviceWorker.ready` never settles for one
  /// that does not control the page.
  private async registration(): Promise<ServiceWorkerRegistration> {
    const reg = (await this.existing()) ?? (await navigator.serviceWorker.register(worker, { scope }));
    for (let i = 0; reg.active == null && i < 50; i++) {
      await new Promise((r) => setTimeout(r, 100));
    }
    if (reg.active == null) throw new Error('The notification service did not start. Reload and try again.');
    return reg;
  }

  async current(): Promise<PushKeys | null> {
    if (!this.supported) return null;
    const reg = await this.existing();
    if (!reg) return null;
    const sub = await reg.pushManager.getSubscription();
    return sub == null ? null : keysOf(sub);
  }

  async subscribe(vapidPublicKey: string): Promise<PushKeys | null> {
    if (!this.supported) return null;
    if (this.permission !== 'granted') {
      const answer = await Notification.requestPermission();
      if (answer !== 'granted') return null;
    }
    const reg = await this.registration();
    const existing = await reg.pushManager.getSubscription();
    if (existing) return keysOf(existing);
    const sub = await reg.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: base64UrlBytes(vapidPublicKey),
    });
    return keysOf(sub);
  }

  async unsubscribe(): Promise<string | null> {
    if (!this.supported) return null;
    const reg = await this.existing();
    const sub = await reg?.pushManager.getSubscription();
    if (!sub) return null;
    const endpoint = sub.endpoint;
    await sub.unsubscribe();
    return endpoint;
  }

  onNotificationOpened(open: (link: string) => void): () => void {
    if (typeof navigator === 'undefined' || !('serviceWorker' in navigator)) return () => {};
    const listener = (event: MessageEvent) => {
      const data = event.data;
      if (data && typeof data === 'object' && data.type === 'open-link' && typeof data.link === 'string') {
        open(data.link);
      }
    };
    navigator.serviceWorker.addEventListener('message', listener);
    return () => navigator.serviceWorker.removeEventListener('message', listener);
  }
}

function keysOf(sub: PushSubscription): PushKeys {
  return { endpoint: sub.endpoint, p256dh: base64Url(sub.getKey('p256dh')), auth: base64Url(sub.getKey('auth')) };
}

function base64Url(buffer: ArrayBuffer | null): string {
  if (buffer == null) return '';
  let binary = '';
  for (const b of new Uint8Array(buffer)) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function base64UrlBytes(key: string): Uint8Array<ArrayBuffer> {
  const padded = key.padEnd(Math.ceil(key.length / 4) * 4, '=').replace(/-/g, '+').replace(/_/g, '/');
  const binary = atob(padded);
  const out = new Uint8Array(new ArrayBuffer(binary.length));
  for (let i = 0; i < binary.length; i++) out[i] = binary.charCodeAt(i);
  return out;
}

/// A browser without push, for tests.
export const noPush: BrowserPush = {
  supported: false,
  needsHomeScreenInstall: false,
  permission: 'denied',
  userAgent: '',
  current: async () => null,
  subscribe: async () => null,
  unsubscribe: async () => null,
  onNotificationOpened: () => () => {},
};

export function createBrowserPush(): BrowserPush {
  return typeof window === 'undefined' ? noPush : new WebPush();
}
