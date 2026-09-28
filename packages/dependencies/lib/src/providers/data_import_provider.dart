import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/data_import.dart';
import 'clinic_provider.dart';
import 'supabase_providers.dart';

/// The current clinic's recent patient imports, newest first.
final importBatchesProvider =
    FutureProvider.autoDispose<List<ImportBatch>>((ref) async {
  ref.watch(currentUserIdProvider);
  final clinicId = ref.watch(currentClinicIdProvider);
  if (clinicId == null) return const [];
  return ref.watch(healthRepositoryProvider).fetchImportBatches(clinicId);
});
