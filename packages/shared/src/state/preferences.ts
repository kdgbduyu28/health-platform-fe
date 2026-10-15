import type { AppRole } from '../models/app_role';
import { type ToothNumbering, toothNumberingFromWire } from '../models/dental_chart';
import { createStore, useStore } from './store';

/// Small things this device remembers between visits: which clinic was open
/// last, the email last signed in with, how teeth are numbered, light or
/// dark.
///
/// Nothing here is private or authoritative. It is localStorage, which the
/// user can clear at any time, so every reader has a sensible default and
/// nothing breaks when it is empty. A locked-down browser that refuses
/// storage gets an in-memory copy that lasts as long as the tab.
export class AppPreferences {
  private readonly memory = new Map<string, string>();
  private readonly storage: Storage | null;
  /// Bumped on every write, so the hooks below re-read.
  readonly version = createStore(0);

  constructor(storage?: Storage | null) {
    this.storage = storage === undefined ? AppPreferences.localStorage() : storage;
  }

  private static localStorage(): Storage | null {
    try {
      if (typeof window === 'undefined' || !window.localStorage) return null;
      const probe = '__prefs_probe__';
      window.localStorage.setItem(probe, '1');
      window.localStorage.removeItem(probe);
      return window.localStorage;
    } catch {
      return null;
    }
  }

  /// Remembers for as long as the app runs. For tests.
  static memory(): AppPreferences {
    return new AppPreferences(null);
  }

  getString(key: string): string | null {
    try {
      const stored = this.storage?.getItem(key);
      if (stored != null) return stored;
    } catch {
      // Storage went away mid-session; the memory copy still answers.
    }
    return this.memory.get(key) ?? null;
  }

  setString(key: string, value: string | null): void {
    if (value == null) {
      this.memory.delete(key);
      try {
        this.storage?.removeItem(key);
      } catch {
        // See getString.
      }
    } else {
      this.memory.set(key, value);
      try {
        this.storage?.setItem(key, value);
      } catch {
        // See getString.
      }
    }
    this.version.set((v) => v + 1);
  }

  // ── Keys ─────────────────────────────────────────────────────────────────

  /// The clinic this app last showed. Per app: the same browser may run the
  /// doctor app at one clinic and the patient app at another.
  lastClinicSlug(app: AppRole): string | null {
    return this.getString(`last_clinic.${app}`);
  }

  setLastClinicSlug(app: AppRole, slug: string): void {
    if (this.lastClinicSlug(app) !== slug) this.setString(`last_clinic.${app}`, slug);
  }

  get lastEmail(): string | null {
    return this.getString('auth.last_email');
  }

  setLastEmail(email: string | null): void {
    this.setString('auth.last_email', email);
  }

  /// The policy versions ticked on the create-account form just before
  /// leaving for Google, as `privacy@…,terms@…`. Recorded against the account
  /// once Google sends the browser back signed in, then cleared.
  get pendingPolicyAck(): string | null {
    return this.getString('auth.pending_policy_ack');
  }

  setPendingPolicyAck(value: string | null): void {
    this.setString('auth.pending_policy_ack', value);
  }

  /// The front desk tablet's hand-off in progress, as JSON (see
  /// KioskSession). Kept so a reload mid-form still lands on the form, not on
  /// the clinic's patient list.
  kioskSession(app: AppRole): string | null {
    return this.getString(`kiosk.${app}`);
  }

  setKioskSession(app: AppRole, json: string | null): void {
    this.setString(`kiosk.${app}`, json);
  }

  get toothNumbering(): ToothNumbering {
    return toothNumberingFromWire(this.getString('dental.numbering'));
  }

  setToothNumbering(n: ToothNumbering): void {
    this.setString('dental.numbering', n);
  }

  /// Light, dark, or whatever the device is set to (the default). One for
  /// all four apps: it is how this device should look, not a per-app choice.
  get themeMode(): ThemeMode {
    const v = this.getString('display.theme');
    return v === 'light' || v === 'dark' ? v : 'system';
  }

  setThemeMode(mode: ThemeMode): void {
    this.setString('display.theme', mode === 'system' ? null : mode);
  }

  get textSize(): TextSize {
    const v = this.getString('display.text_size');
    return v === 'large' || v === 'larger' ? v : 'normal';
  }

  setTextSize(size: TextSize): void {
    this.setString('display.text_size', size === 'normal' ? null : size);
  }

  /// How this app lays out a day's visits: a list, or a board by status. Per
  /// app, like the clinic: a doctor may like the board while the front desk
  /// on the same browser keeps the list.
  appointmentView(app: AppRole): AppointmentView {
    return this.getString(`appointments.view.${app}`) === 'board' ? 'board' : 'list';
  }

  setAppointmentView(app: AppRole, view: AppointmentView): void {
    this.setString(`appointments.view.${app}`, view === 'list' ? null : view);
  }

  /// The calendar's last month / week / day, by name; null until one is
  /// picked, when the calendar goes by the screen's width.
  calendarView(app: AppRole): string | null {
    return this.getString(`calendar.view.${app}`);
  }

  setCalendarView(app: AppRole, view: string): void {
    this.setString(`calendar.view.${app}`, view);
  }

  /// Forgets everything above except the clinic and the tablet hand-off,
  /// which are not preferences: dropping a kiosk session here would hand the
  /// app back to whoever holds the tablet.
  resetDisplay(): void {
    this.setString('display.theme', null);
    this.setString('display.text_size', null);
    this.setString('dental.numbering', null);
  }
}

export type ThemeMode = 'system' | 'light' | 'dark';

/// Text larger than the device's own setting, for reading at arm's length — a
/// front desk tablet, or a patient without their glasses. It multiplies the
/// browser's own size rather than replacing it.
export type TextSize = 'normal' | 'large' | 'larger';
export const textSizes: readonly TextSize[] = ['normal', 'large', 'larger'];
export const textSizeMeta: Record<TextSize, { scale: number; label: string }> = {
  normal: { scale: 1.0, label: 'Default' },
  large: { scale: 1.15, label: 'Large' },
  larger: { scale: 1.3, label: 'Larger' },
};

/// A day's visits as cards in time order, or as columns by where each visit
/// stands (see AppointmentBoard).
export type AppointmentView = 'list' | 'board';

/// The device's preferences. One per page.
export const preferences = new AppPreferences();

/// Re-renders when any preference changes, and returns [read]'s answer.
export function usePreference<T>(read: (p: AppPreferences) => T): T {
  useStore(preferences.version);
  return read(preferences);
}
