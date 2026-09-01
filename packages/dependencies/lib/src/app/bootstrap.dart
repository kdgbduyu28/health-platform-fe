import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

/// Starts Supabase before `runApp`. Every app's `main()` must await this —
/// `Supabase.instance.client` throws if it is read first.
///
/// The session is persisted by supabase_flutter, so a returning user is
/// already signed in by the time the first frame builds.
Future<void> initializeHealthPlatform() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  );
}
