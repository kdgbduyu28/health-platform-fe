import {
  Hct,
  MaterialDynamicColors,
  SchemeTonalSpot,
  argbFromHex,
  hexFromArgb,
} from '@material/material-color-utilities';
import { MD3DarkTheme, MD3LightTheme, configureFonts, useTheme } from 'react-native-paper';
import type { MD3Theme } from 'react-native-paper';

import type { Clinic } from '../models/clinic';

/// Platform-level brand constants.
///
/// Clinic branding comes from each clinic's row at runtime. These are what
/// shows when there is no clinic yet — the sign-in screen, before anyone is
/// known — and what a clinic falls back to when it has not set its own.
export const Brand = {
  /// A deliberately neutral default. It is NOT any client's colour: the
  /// sign-in screen is shared by every clinic on the platform, and D-Touch's
  /// brown there would brand every other clinic's login as D-Touch. D-Touch
  /// keeps its brown from its own clinic row once signed in.
  platformSeed: '#3D5A80',

  /// Prefix for a clinic's `logo_url` / `wordmark_url` meaning "bundled in
  /// this package" rather than a hosted file. A stopgap for artwork that
  /// predates logo uploads (D-Touch's lockup ships this way); hosted URLs are
  /// the normal path for a new clinic.
  bundledAssetScheme: 'asset:',
};

/// Every colour role a screen may use: Paper's, plus the surface containers
/// Material 3 added since (the cards, rails and sheets use those).
export type AppColors = MD3Theme['colors'] & {
  surfaceDim: string;
  surfaceBright: string;
  surfaceContainerLowest: string;
  surfaceContainerLow: string;
  surfaceContainer: string;
  surfaceContainerHigh: string;
  surfaceContainerHighest: string;
};

export type AppTheme = Omit<MD3Theme, 'colors'> & { colors: AppColors };

export function useAppTheme(): AppTheme {
  return useTheme<AppTheme>();
}

/// The scheme Flutter's `ColorScheme.fromSeed` makes: Material's "tonal spot"
/// dynamic scheme from the seed, so a clinic's colours match what it had.
function schemeColors(seed: string, dark: boolean): AppColors {
  const scheme = new SchemeTonalSpot(Hct.fromInt(argbFromHex(seed)), dark, 0);
  const c = (role: { getArgb(s: SchemeTonalSpot): number }) => hexFromArgb(role.getArgb(scheme));
  const D = MaterialDynamicColors;
  const base = dark ? MD3DarkTheme.colors : MD3LightTheme.colors;
  const surfaceContainerLow = c(D.surfaceContainerLow);
  const surfaceContainer = c(D.surfaceContainer);
  const surfaceContainerHigh = c(D.surfaceContainerHigh);
  const surfaceContainerHighest = c(D.surfaceContainerHighest);
  const onSurface = c(D.onSurface);
  return {
    ...base,
    primary: c(D.primary),
    onPrimary: c(D.onPrimary),
    primaryContainer: c(D.primaryContainer),
    onPrimaryContainer: c(D.onPrimaryContainer),
    secondary: c(D.secondary),
    onSecondary: c(D.onSecondary),
    secondaryContainer: c(D.secondaryContainer),
    onSecondaryContainer: c(D.onSecondaryContainer),
    tertiary: c(D.tertiary),
    onTertiary: c(D.onTertiary),
    tertiaryContainer: c(D.tertiaryContainer),
    onTertiaryContainer: c(D.onTertiaryContainer),
    error: c(D.error),
    onError: c(D.onError),
    errorContainer: c(D.errorContainer),
    onErrorContainer: c(D.onErrorContainer),
    // Material 3 retired `background`; it is the surface now.
    background: c(D.surface),
    onBackground: onSurface,
    surface: c(D.surface),
    onSurface,
    surfaceVariant: surfaceContainerHighest,
    onSurfaceVariant: c(D.onSurfaceVariant),
    outline: c(D.outline),
    outlineVariant: c(D.outlineVariant),
    inverseSurface: c(D.inverseSurface),
    inverseOnSurface: c(D.inverseOnSurface),
    inversePrimary: c(D.inversePrimary),
    shadow: c(D.shadow),
    scrim: c(D.scrim),
    surfaceDisabled: withAlpha(onSurface, 0.12),
    onSurfaceDisabled: withAlpha(onSurface, 0.38),
    backdrop: withAlpha(c(D.scrim), 0.32),
    elevation: {
      level0: 'transparent',
      level1: surfaceContainerLow,
      level2: surfaceContainer,
      level3: surfaceContainerHigh,
      level4: surfaceContainerHigh,
      level5: surfaceContainerHighest,
    },
    surfaceDim: c(D.surfaceDim),
    surfaceBright: c(D.surfaceBright),
    surfaceContainerLowest: c(D.surfaceContainerLowest),
    surfaceContainerLow,
    surfaceContainer,
    surfaceContainerHigh,
    surfaceContainerHighest,
  };
}

/// `#RRGGBB` at [alpha] (0–1), as `rgba()`.
export function withAlpha(hex: string, alpha: number): string {
  const n = parseInt(hex.slice(1, 7), 16);
  return `rgba(${(n >> 16) & 255}, ${(n >> 8) & 255}, ${n & 255}, ${alpha})`;
}

/// [a] → [b] by [t] (0–1), both `#RRGGBB`.
export function lerpColor(a: string, b: string, t: number): string {
  const pa = parseInt(a.slice(1, 7), 16);
  const pb = parseInt(b.slice(1, 7), 16);
  const ch = (shift: number) => {
    const x = (pa >> shift) & 255;
    const y = (pb >> shift) & 255;
    return Math.round(x + (y - x) * t);
  };
  return `#${[ch(16), ch(8), ch(0)].map((v) => v.toString(16).padStart(2, '0')).join('').toUpperCase()}`;
}

/// This colour, lifted toward white on a dark theme. The status colours are
/// mid-tones picked for a light surface; on a dark one they turn muddy
/// (purple "Waiting", grey "No-show").
export function readableIn(color: string, dark: boolean): string {
  return dark ? lerpColor(color, '#FFFFFF', 0.45) : color;
}

export function useReadable(): (color: string) => string {
  const dark = useAppTheme().dark;
  return (color) => readableIn(color, dark);
}

const themeCache = new Map<string, AppTheme>();

/// The app theme for [clinic], or the platform theme when there is no clinic
/// yet (signed out) or the clinic has not set a colour. The dark theme is
/// the same clinic colour seeded dark, so a clinic keeps its identity either
/// way. [textScale] enlarges every type style on top of the browser's size.
export function buildClinicTheme(clinic: Clinic | null, dark: boolean, textScale = 1): AppTheme {
  const seed = clinic?.seedColor ?? Brand.platformSeed;
  const key = `${seed}|${dark}|${textScale}`;
  const cached = themeCache.get(key);
  if (cached) return cached;

  const base = dark ? MD3DarkTheme : MD3LightTheme;
  const fonts =
    textScale === 1
      ? base.fonts
      : configureFonts({
          config: Object.fromEntries(
            Object.entries(base.fonts).map(([variant, style]) => [
              variant,
              typeof style === 'object' && style != null && 'fontSize' in style
                ? { ...style, fontSize: style.fontSize * textScale, lineHeight: style.lineHeight * textScale }
                : style,
            ]),
          ),
        });
  const theme: AppTheme = {
    ...base,
    dark,
    roundness: 3,
    fonts: fonts as MD3Theme['fonts'],
    colors: schemeColors(seed, dark),
  };
  themeCache.set(key, theme);
  return theme;
}
