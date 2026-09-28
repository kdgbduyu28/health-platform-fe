import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/appointment.dart';
import '../providers/appointments_provider.dart';
import '../providers/clinic_provider.dart';
import '../providers/supabase_providers.dart';

/// One calendar page: visits starting in [from, to), local wall-clock days.
typedef CalendarRange = ({DateTime from, DateTime to});

/// The visits at the current clinic in [range] that the signed-in user may
/// see — RLS decides whose; the calendar screen narrows further (one doctor,
/// one patient).
///
/// A page inside the loaded working set (a week ago onward) is read from it,
/// so it moves the moment a visit is booked, checked in or moved. A page that
/// reaches further back is fetched on its own, and fetched again whenever the
/// working set reloads — a refresh anywhere refreshes it too.
final calendarAppointmentsProvider = Provider.autoDispose
    .family<AsyncValue<List<Appointment>>, CalendarRange>((ref, range) {
  if (!range.from.isBefore(ref.watch(appointmentWindowStartProvider))) {
    return ref.watch(clinicAppointmentsProvider).whenData((list) => [
          for (final a in list)
            if (!a.dateTime.isBefore(range.from) && a.dateTime.isBefore(range.to))
              a,
        ]);
  }
  return ref.watch(_calendarRangeFetchProvider(range));
});

final _calendarRangeFetchProvider = FutureProvider.autoDispose
    .family<List<Appointment>, CalendarRange>((ref, range) async {
  // Only to follow reloads of the working set; the rows come from below.
  ref.watch(appointmentsProvider.select((v) => v.value));
  final clinicId = ref.watch(currentClinicIdProvider);
  if (clinicId == null) return const [];
  return ref.watch(healthRepositoryProvider).fetchAppointmentsBetween(
        clinicId: clinicId,
        from: range.from,
        to: range.to,
      );
});
