import { useNavigation, useRouter } from 'expo-router';
import { useCallback, useMemo } from 'react';

import { useRouteClinicSlug } from '../queries/clinic';

type NavRoute = { name: string; params?: Record<string, unknown> };

/// The URL path a route of a stack stands for: its file name with the
/// parameters filled in and the (group) folders dropped.
export function routePath(route: NavRoute): string {
  const params = route.params ?? {};
  const segments = route.name
    .split('/')
    .filter((s) => !(s.startsWith('(') && s.endsWith(')')) && s !== 'index')
    .map((s) => {
      const m = /^\[(?:\.\.\.)?(.+)\]$/.exec(s);
      if (!m) return s;
      const v = params[m[1]];
      return Array.isArray(v) ? v.join('/') : String(v ?? '');
    });
  return `/${segments.join('/')}`;
}

/// Navigation inside the current clinic, so screens never spell out a slug:
///
///   nav.go('/appointments');   // → /dtouchdental/appointments
export function useClinicNav() {
  const router = useRouter();
  const navigation = useNavigation();
  const slug = useRouteClinicSlug() ?? '';

  const path = useCallback((subpath: string) => `/${slug}${subpath}`, [slug]);

  /// Replaces everything on screen with [location]: go_router's `go`. The
  /// browser's back button still returns to where they were.
  const goTo = useCallback(
    (location: string) => {
      if (router.canDismiss()) router.dismissAll();
      router.replace(location as never);
    },
    [router],
  );

  return useMemo(
    () => ({
      /// The slug of the clinic this screen belongs to.
      slug,
      /// [subpath] (starting with `/`) under the current clinic.
      path,
      go: (subpath: string) => goTo(path(subpath)),
      goTo,
      push: (subpath: string) => router.push(path(subpath) as never),
      pushTo: (location: string) => router.push(location as never),

      /// Opens [subpath] — or, when that page is already open further down
      /// the stack, goes back to it instead of stacking a second copy.
      ///
      /// For pages that link to each other: a visit links to the patient's
      /// history and the history links back to the visit, so pushing both
      /// ways grows the stack on every tap, and Back walks the same two pages
      /// over and over.
      open: (subpath: string) => {
        const target = path(subpath);
        const state = navigation.getState() as { index: number; routes: NavRoute[] } | undefined;
        const paths = state?.routes.map(routePath) ?? [];
        const at = paths.lastIndexOf(target);
        if (state == null || at === -1 || at === state.index) {
          router.push(target as never);
        } else {
          router.dismiss(state.index - at);
        }
      },

      /// Back one page, or to [fallback] (under the clinic) when this page
      /// was opened directly — a shared link or a reload — and there is
      /// nothing to go back to.
      back: (fallback?: string) => {
        if (router.canGoBack()) router.back();
        else if (fallback != null) goTo(path(fallback));
      },
      canGoBack: () => router.canGoBack(),
    }),
    [slug, path, goTo, router, navigation],
  );
}
