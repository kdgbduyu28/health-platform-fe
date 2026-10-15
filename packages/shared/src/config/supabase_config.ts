/// Connection details for the health-platform Supabase project.
///
/// The publishable key is meant to ship inside client builds — it grants no
/// privileges by itself. Every row it can reach is decided by the Row Level
/// Security policies in health-platform-be, which is why those policies carry
/// the weight here. Anyone can read this key out of a web bundle; that is the
/// designed behaviour, not a leak.
///
/// The `service_role` secret is the opposite: it bypasses RLS entirely and must
/// never appear in this repo or in any client build.
///
/// Each value can be overridden per build without editing source, through
/// Expo's public environment variables:
///
///   EXPO_PUBLIC_SUPABASE_URL=https://xxx.supabase.co \
///   EXPO_PUBLIC_SUPABASE_KEY=sb_publishable_xxx npx expo export -p web
///
/// Expo inlines `process.env.EXPO_PUBLIC_*` at build time, and only when each
/// is written out in full like this — not looked up by a computed name.
export const SupabaseConfig = {
  url: process.env.EXPO_PUBLIC_SUPABASE_URL || 'https://nmjtfjbamhryiajrwckg.supabase.co',

  publishableKey: process.env.EXPO_PUBLIC_SUPABASE_KEY || 'sb_publishable_5sVEfS97leh1iUGr3b5OoA_unE54G3B',

  /// The platform's VAPID public key, which browsers subscribe to Web Push
  /// with. Public by design, like the key above; its private half is an Edge
  /// Function secret (health-platform-be, supabase/functions/.env). The two
  /// must be a pair, or every push is refused.
  vapidPublicKey:
    process.env.EXPO_PUBLIC_VAPID_PUBLIC_KEY ||
    'BDBiuAUhyEtalMV851jQgWZhWi_8azbFbRjmUwLZN76FDMV7RHOC4mZzOH4KzhtrAmyoALPDyFcOrI-UczHrclQ',

  /// The Cloudflare Turnstile site key behind the human check on sign-in,
  /// sign-up and password reset. Public, like the keys above; its secret half
  /// is set in Supabase Auth (Attack Protection). The widget only runs on the
  /// hostnames listed for it in Cloudflare (the four rowph*.pages.dev apps).
  ///
  /// Set EXPO_PUBLIC_TURNSTILE_SITE_KEY to `off` to build without the check.
  /// Ship a build with this set BEFORE turning CAPTCHA on in Supabase: from
  /// then on, a build without it cannot sign anyone in.
  turnstileSiteKey: turnstileKey(process.env.EXPO_PUBLIC_TURNSTILE_SITE_KEY),
};

function turnstileKey(value: string | undefined): string {
  if (value === 'off') return '';
  return value || '0x4AAAAAAFKL31aTz1AJa7Ad';
}
