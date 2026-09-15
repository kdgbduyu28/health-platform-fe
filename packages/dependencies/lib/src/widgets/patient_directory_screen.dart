import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/appointment.dart';
import '../models/appointment_status.dart';
import '../models/patient.dart';
import '../providers/appointments_provider.dart';
import '../providers/catalog_provider.dart';
import 'async_view.dart';
import 'clinic_title.dart';

/// Every chart held at the current clinic, searchable by name or phone.
///
/// Shared by the staff apps; each passes [onOpenPatient] to route to its own
/// patient history page. RLS already limits the list to this clinic, so the
/// search only narrows what the database allowed.
class PatientDirectoryScreen extends ConsumerStatefulWidget {
  const PatientDirectoryScreen({super.key, required this.onOpenPatient});

  final void Function(Patient patient) onOpenPatient;

  @override
  ConsumerState<PatientDirectoryScreen> createState() =>
      _PatientDirectoryScreenState();
}

class _PatientDirectoryScreenState
    extends ConsumerState<PatientDirectoryScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final patientsAsync = ref.watch(patientsProvider);
    final appointments =
        ref.watch(clinicAppointmentsProvider).value ?? const <Appointment>[];

    // Completed visits per chart, from the appointments already loaded.
    final visitCount = <String, int>{};
    final lastVisit = <String, DateTime>{};
    for (final a in appointments) {
      if (a.status != AppointmentStatus.completed) continue;
      final id = a.patient.id;
      visitCount.update(id, (n) => n + 1, ifAbsent: () => 1);
      final previous = lastVisit[id];
      if (previous == null || a.dateTime.isAfter(previous)) {
        lastVisit[id] = a.dateTime;
      }
    }

    final patients = (patientsAsync.value ?? const <Patient>[])
        .where((p) => p.matches(_query))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Patients',
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: cs.onSurfaceVariant)),
            ClinicTitle(
              markSize: 20,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _search,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Search by name or phone…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() {
                          _search.clear();
                          _query = '';
                        }),
                      ),
              ),
            ),
          ),
          Expanded(
            child: !patientsAsync.hasValue
                ? AsyncView(
                    value: patientsAsync,
                    onRetry: () => ref.invalidate(patientsProvider),
                    builder: (_) => const SizedBox.shrink(),
                  )
                : RefreshIndicator(
                    onRefresh: () => Future.wait([
                      ref.refresh(patientsProvider.future),
                      ref.read(appointmentsProvider.notifier).refresh(),
                    ]),
                    child: patients.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              const SizedBox(height: 80),
                              Center(
                                child: Text(
                                  _query.isEmpty
                                      ? 'No patients yet.'
                                      : 'No patients match "$_query".',
                                  style: theme.textTheme.titleMedium,
                                ),
                              ),
                            ],
                          )
                        : ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            itemCount: patients.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, i) {
                              final p = patients[i];
                              final last = lastVisit[p.id];
                              return Card(
                                margin: EdgeInsets.zero,
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: cs.primaryContainer,
                                    child: Text(p.initials,
                                        style: TextStyle(
                                            color: cs.onPrimaryContainer,
                                            fontWeight: FontWeight.bold)),
                                  ),
                                  title: Text(p.name,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600)),
                                  subtitle: Text([
                                    if (p.phone.isNotEmpty) p.phone,
                                    last == null
                                        ? 'No visits yet'
                                        : 'Last visit ${DateFormat('MMM d, y').format(last)}',
                                  ].join(' · ')),
                                  trailing: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text('${visitCount[p.id] ?? 0}',
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: cs.primary,
                                              fontSize: 16)),
                                      Text('visits',
                                          style: TextStyle(
                                              fontSize: 10,
                                              color: cs.onSurfaceVariant)),
                                    ],
                                  ),
                                  onTap: () => widget.onOpenPatient(p),
                                ),
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}
