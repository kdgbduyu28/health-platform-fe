import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_role.dart';
import '../models/dental_chart.dart';
import 'clinic_provider.dart';
import 'supabase_providers.dart';

/// Whether the clinic being shown charts teeth — its vertical's
/// `chart_kind` is `dental`. Every dental screen checks this, so an eye clinic
/// never sees a tooth.
final clinicChartsTeethProvider = Provider<bool>(
  (ref) => ref.watch(currentClinicProvider).value?.isDental ?? false,
);

/// Every entry on one chart's dental chart, oldest first.
///
/// Staff read the table (with notes); the patient app reads the patient's own
/// chart through `patient_dental_chart`, which leaves the notes out — a
/// patient has no direct read of the table at all.
final dentalEntriesProvider = FutureProvider.autoDispose
    .family<List<DentalEntry>, String>((ref, patientId) {
  ref.watch(currentUserIdProvider);
  final repo = ref.watch(healthRepositoryProvider);
  return ref.watch(appRoleProvider) == AppRole.patient
      ? repo.fetchMyDentalChart(patientId)
      : repo.fetchDentalEntries(patientId);
});

/// One chart's entries folded into the picture: see [DentalChart].
final dentalChartProvider = Provider.autoDispose
    .family<AsyncValue<DentalChart>, String>(
  (ref, patientId) =>
      ref.watch(dentalEntriesProvider(patientId)).whenData(DentalChart.new),
);
