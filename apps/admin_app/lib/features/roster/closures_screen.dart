import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:api_sdk/api_sdk.dart';

/// `/:clinic/settings/closures` — days nobody can book: holidays, when the
/// whole clinic is closed, and a doctor's leave.
///
/// These only stop NEW bookings (`available_slots` offers nothing on those
/// days). Visits already booked are left alone on purpose — the clinic
/// should call those patients, not have their visits vanish — so adding
/// time off says how many there are.
class ClosuresScreen extends ConsumerWidget {
  const ClosuresScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timeOff = ref.watch(timeOffProvider);
    final roster = ref.watch(rosterProvider).value ?? const <Doctor>[];
    String who(TimeOff t) {
      if (t.isClosure) return 'Whole clinic closed';
      for (final d in roster) {
        if (d.id == t.doctorId) return 'Dr. ${d.name}';
      }
      return 'A doctor';
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Closures & leave')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final saved = await showDialog<bool>(
            context: context,
            builder: (_) => const _TimeOffEditor(),
          );
          if (saved == true) invalidateCatalog(ref);
        },
        icon: const Icon(Icons.event_busy),
        label: const Text('Add'),
      ),
      body: AsyncView(
        value: timeOff,
        onRetry: () => ref.invalidate(timeOffProvider),
        builder: (entries) => entries.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'No closures or leave coming up. Add holidays and '
                    'doctors\' days off so patients cannot book them.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                itemCount: entries.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final t = entries[i];
                  final cs = Theme.of(context).colorScheme;
                  return Card(
                    child: ListTile(
                      leading: Icon(
                        t.isClosure ? Icons.store_mall_directory_outlined : Icons.beach_access_outlined,
                        color: t.isClosure ? cs.error : cs.primary,
                      ),
                      title: Text(who(t),
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text([
                        formatDayRange(t.startsOn, t.endsOn),
                        if (t.reason != null) t.reason!,
                      ].join(' · ')),
                      trailing: IconButton(
                        tooltip: 'Remove',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _remove(context, ref, t, who(t)),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  Future<void> _remove(
      BuildContext context, WidgetRef ref, TimeOff t, String who) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove this?'),
        content: Text('$who, ${formatDayRange(t.startsOn, t.endsOn)}. '
            'Patients will be able to book those days again.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(healthRepositoryProvider).deleteTimeOff(t.id);
      invalidateCatalog(ref);
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(describeError(e)),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }
}

/// `Mon, Dec 22` or `Mon, Dec 22 – Fri, Jan 2`.
String formatDayRange(DateTime start, DateTime end) {
  final f = DateFormat('EEE, MMM d');
  return DateUtils.isSameDay(start, end)
      ? f.format(start)
      : '${f.format(start)} – ${f.format(end)}';
}

class _TimeOffEditor extends ConsumerStatefulWidget {
  const _TimeOffEditor();

  @override
  ConsumerState<_TimeOffEditor> createState() => _TimeOffEditorState();
}

class _TimeOffEditorState extends ConsumerState<_TimeOffEditor> {
  /// Null: the whole clinic.
  String? _doctorId;
  DateTimeRange? _days;
  final _reason = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _pickDays() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDateRangePicker(
      context: context,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
      initialDateRange: _days,
      helpText: 'Days off',
    );
    if (picked != null) setState(() => _days = picked);
  }

  /// Visits still on the calendar on those days, for whoever is off.
  int _affected(List<Appointment> visits) {
    final days = _days;
    if (days == null) return 0;
    final last = days.end.add(const Duration(days: 1));
    return visits
        .where((a) =>
            a.status.holdsTime &&
            a.status.isOpen &&
            (_doctorId == null || a.doctor.id == _doctorId) &&
            !a.dateTime.isBefore(days.start) &&
            a.dateTime.isBefore(last))
        .length;
  }

  Future<void> _save() async {
    final days = _days;
    if (_busy) return;
    if (days == null) {
      setState(() => _error = 'Pick the days.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(healthRepositoryProvider).addTimeOff(
            clinicId: ref.read(currentClinicIdProvider)!,
            doctorId: _doctorId,
            startsOn: days.start,
            endsOn: days.end,
            reason: _reason.text,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final doctors = [
      for (final d in ref.watch(rosterProvider).value ?? const <Doctor>[])
        if (d.isActive) d,
    ];
    final affected = _affected(
        ref.watch(clinicAppointmentsProvider).value ?? const <Appointment>[]);

    return AlertDialog(
      title: const Text('Add closure or leave'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String?>(
                initialValue: _doctorId,
                decoration: const InputDecoration(labelText: 'Who is off'),
                items: [
                  const DropdownMenuItem(
                      value: null, child: Text('Whole clinic (closed)')),
                  for (final d in doctors)
                    DropdownMenuItem(value: d.id, child: Text('Dr. ${d.name}')),
                ],
                onChanged: (v) => setState(() => _doctorId = v),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _pickDays,
                icon: const Icon(Icons.date_range),
                label: Text(_days == null
                    ? 'Pick days'
                    : formatDayRange(_days!.start, _days!.end)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _reason,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Reason (optional)',
                  hintText: 'Holiday, conference, leave…',
                ),
              ),
              if (affected > 0) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$affected booked ${affected == 1 ? 'visit falls' : 'visits fall'} '
                    'on these days. ${affected == 1 ? 'It stays' : 'They stay'} '
                    'booked — call ${affected == 1 ? 'that patient' : 'those patients'} '
                    'to rebook or cancel.',
                    style: TextStyle(color: cs.onErrorContainer),
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: cs.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
          onPressed: _busy ? null : _save,
          child: const Text('Add'),
        ),
      ],
    );
  }
}
