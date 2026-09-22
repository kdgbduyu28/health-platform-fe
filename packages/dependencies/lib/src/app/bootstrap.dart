import 'package:flutter/widgets.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

/// Starts Supabase before `runApp`. Every app's `main()` must await this —
/// `Supabase.instance.client` throws if it is read first.
///
/// The session is persisted by supabase_flutter, so a returning user is
/// already signed in by the time the first frame builds.
Future<void> initializeHealthPlatform() async {
  // Real paths (/dtouchdental/book), not the web default of /#/dtouchdental/book:
  // a clinic's link is its address. Netlify's `/* /index.html 200` rewrite
  // serves the app at any path. A no-op off the web.
  usePathUrlStrategy();
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  );
}
