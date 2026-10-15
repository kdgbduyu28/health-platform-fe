import { createElement, useEffect, useRef, useState, useSyncExternalStore } from 'react';
import { View } from 'react-native';
import { Button, Text } from 'react-native-paper';

import { SupabaseConfig } from '../config/supabase_config';
import { inBrowser } from '../platform/browser';
import { useAppTheme } from '../theme/clinic_theme';
import { Icon } from '../ui/icon';

const scriptUrl = 'https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit';

type TurnstileApi = {
  render(container: HTMLElement, options: Record<string, unknown>): string | undefined;
  reset(id: string): void;
  remove(id: string): void;
};

/// The Turnstile script, loaded once per page and only when a screen asks
/// for it, so signed-in pages never fetch it.
let loading: Promise<TurnstileApi> | null = null;

function turnstileApi(): Promise<TurnstileApi> {
  loading ??= new Promise<TurnstileApi>((resolve, reject) => {
    const script = document.createElement('script');
    script.src = scriptUrl;
    script.async = true;
    script.onload = () => resolve((window as unknown as { turnstile: TurnstileApi }).turnstile);
    script.onerror = () => {
      loading = null; // let the next widget try again
      reject(
        new Error(
          'The security check could not load. Check your connection, or allow challenges.cloudflare.com if a content blocker is on.',
        ),
      );
    };
    document.head.append(script);
  });
  return loading;
}

/// The "are you human" check in front of sign-in, sign-up and password reset.
///
/// Supabase Auth refuses those three requests without a fresh Cloudflare
/// Turnstile token once CAPTCHA protection is on for the project (see the
/// backend README), so the check is enforced by the server, not by this form.
/// With no site key configured, or outside a browser, it is off: [token]
/// answers null and HumanCheck draws nothing.
export class HumanCheckController {
  constructor(readonly siteKey: string = SupabaseConfig.turnstileSiteKey) {}

  get enabled(): boolean {
    return this.siteKey !== '' && inBrowser();
  }

  private readyToken: string | null = null;
  private waiting: ((token: string | null) => void) | null = null;
  private resetWidget: (() => void) | null = null;
  private listeners = new Set<() => void>();
  private snapshot = { error: null as string | null, interactive: false };

  /// Why the check could not finish, and whether Cloudflare wants a click:
  /// only then does a hidden check need showing.
  get state() {
    return this.snapshot;
  }

  subscribe = (l: () => void) => {
    this.listeners.add(l);
    return () => this.listeners.delete(l);
  };

  private emit(next: Partial<typeof this.snapshot>) {
    this.snapshot = { ...this.snapshot, ...next };
    for (const l of [...this.listeners]) l();
  }

  /// The token for the next auth request, or null when the check is off.
  ///
  /// Tokens are single-use: this hands the current one over, and [reset]
  /// must follow the request that spent it. Usually one is ready by the time
  /// the form is filled in; if not, this waits for it.
  ///
  /// Never throws. If the check failed or has not finished, the request goes
  /// without a token and Supabase decides: while CAPTCHA is off there, a
  /// blocked or broken widget cannot lock anyone out; once it is on, Supabase
  /// refuses and the person is told to let the check finish.
  token(timeoutMs = 15_000): Promise<string | null> {
    if (!this.enabled || this.snapshot.error != null) return Promise.resolve(null);
    if (this.readyToken != null) {
      const t = this.readyToken;
      this.readyToken = null;
      return Promise.resolve(t);
    }
    return new Promise((resolve) => {
      const timer = setTimeout(() => {
        if (this.waiting === done) this.waiting = null;
        resolve(null);
      }, timeoutMs);
      const done = (t: string | null) => {
        clearTimeout(timer);
        resolve(t);
      };
      this.waiting = done;
    });
  }

  /// Fetches a new token after one was spent (or refused).
  reset(): void {
    this.readyToken = null;
    this.resetWidget?.();
  }

  /// @internal — the widget's side.
  attach(reset: () => void) {
    this.resetWidget = reset;
    this.readyToken = null;
    this.emit({ error: null, interactive: false });
  }

  detach(reset: () => void) {
    if (this.resetWidget === reset) this.resetWidget = null;
  }

  gotToken(token: string) {
    if (this.waiting) {
      const w = this.waiting;
      this.waiting = null;
      w(token);
    } else {
      this.readyToken = token;
    }
    this.emit({ error: null });
  }

  lostToken() {
    this.readyToken = null;
    this.emit({});
  }

  failed(message: string) {
    this.readyToken = null;
    if (this.waiting) {
      const w = this.waiting;
      this.waiting = null;
      w(null);
    }
    this.emit({ error: message });
  }

  setInteractive(interactive: boolean) {
    this.emit({ interactive });
  }
}

/// One controller per form, for its lifetime.
export function useHumanCheck(): HumanCheckController {
  const ref = useRef<HumanCheckController | null>(null);
  ref.current ??= new HumanCheckController();
  return ref.current;
}

/// Where a controller's Turnstile widget sits in a form.
///
/// [alwaysVisible] shows Cloudflare's "Verifying… / Success" box. Without it
/// the check runs unseen and only appears if Cloudflare wants a click, which
/// is how sign-in stays quiet until someone gets the password wrong a few
/// times. Changing [action] or [alwaysVisible] renders a new widget, because
/// Turnstile fixes both when it renders.
export function HumanCheck({
  controller,
  action,
  alwaysVisible = true,
}: {
  controller: HumanCheckController;
  /// Shows up in Cloudflare's analytics: `sign-in`, `sign-up`, `reset`.
  action: string;
  alwaysVisible?: boolean;
}) {
  const { colors, dark } = useAppTheme();
  const host = useRef<HTMLDivElement | null>(null);
  const [attempt, setAttempt] = useState(0);
  const state = useSyncExternalStore(controller.subscribe, () => controller.state);

  useEffect(() => {
    if (!controller.enabled || host.current == null) return;
    const container = host.current;
    let id: string | undefined;
    let api: TurnstileApi | null = null;
    let removed = false;
    const reset = () => {
      if (id != null) api?.reset(id);
    };
    controller.attach(reset);
    turnstileApi()
      .then((t) => {
        if (removed) return;
        api = t;
        id = t.render(container, {
          sitekey: controller.siteKey,
          action,
          theme: dark ? 'dark' : 'light',
          // Hidden until Cloudflare actually needs a click; always shown
          // once the screen wants the check to be seen.
          appearance: alwaysVisible ? 'always' : 'interaction-only',
          size: 'flexible',
          'refresh-expired': 'auto',
          callback: (token: string) => !removed && controller.gotToken(token),
          'expired-callback': () => !removed && controller.lostToken(),
          'error-callback': (code?: unknown) => {
            if (!removed) {
              controller.failed(`The security check could not finish${code == null ? '' : ` (${String(code)})`}.`);
            }
          },
          'before-interactive-callback': () => !removed && controller.setInteractive(true),
          'after-interactive-callback': () => !removed && controller.setInteractive(false),
        });
      })
      .catch((e: Error) => !removed && controller.failed(e.message));
    return () => {
      removed = true;
      controller.detach(reset);
      if (id != null) api?.remove(id);
      container.innerHTML = '';
    };
  }, [controller, action, alwaysVisible, dark, attempt]);

  if (!controller.enabled) return null;
  const shown = alwaysVisible || state.interactive;
  return (
    <View>
      {/* Kept on the page at 1px while hidden: the check still has to run. */}
      <View style={{ marginTop: shown ? 16 : 0, height: shown ? 65 : 1, overflow: 'hidden' }}>
        {createElement('div', { ref: host, style: { width: '100%', height: '100%' } })}
      </View>
      {state.error != null && (
        <View style={{ flexDirection: 'row', alignItems: 'center', marginTop: 8, gap: 8 }}>
          <Icon name="shield" size={18} color={colors.error} />
          <Text style={{ flex: 1, color: colors.error, fontSize: 13 }}>{state.error}</Text>
          <Button onPress={() => setAttempt((a) => a + 1)}>Retry</Button>
        </View>
      )}
    </View>
  );
}
