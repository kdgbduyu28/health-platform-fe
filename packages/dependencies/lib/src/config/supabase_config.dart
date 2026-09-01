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
/// Both values can be overridden per build without editing source:
///
///   flutter run --dart-define=SUPABASE_URL=https://xxx.supabase.co \
///               --dart-define=SUPABASE_KEY=sb_publishable_xxx
class SupabaseConfig {
  const SupabaseConfig._();

  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://nmjtfjbamhryiajrwckg.supabase.co',
  );

  static const publishableKey = String.fromEnvironment(
    'SUPABASE_KEY',
    defaultValue: 'sb_publishable_5sVEfS97leh1iUGr3b5OoA_unE54G3B',
  );
}
