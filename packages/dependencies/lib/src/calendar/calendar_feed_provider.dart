import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/supabase_providers.dart';
import 'calendar_links.dart';

/// The signed-in account's calendar feed URL. Asking makes the feed on the
/// first call, so this is read only once the patient opens the subscribe
/// sheet, never on a screen they merely pass through.
final calendarFeedUrlProvider = FutureProvider.autoDispose<String?>((ref) async {
  if (ref.watch(currentUserIdProvider) == null) return null;
  final token =
      await ref.watch(supabaseClientProvider).rpc('my_calendar_feed_token');
  return calendarFeedUrl(token as String);
});

/// A new URL for the feed; every copy of the old one stops working.
Future<void> resetCalendarFeed(WidgetRef ref) async {
  await ref.read(supabaseClientProvider).rpc('reset_calendar_feed_token');
  ref.invalidate(calendarFeedUrlProvider);
}
