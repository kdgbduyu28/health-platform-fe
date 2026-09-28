import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../app/adaptive_layout.dart';
import '../models/appointment.dart';
import '../models/appointment_status.dart';
import '../models/doctor.dart';
import '../providers/catalog_provider.dart';
import '../providers/clinic_provider.dart';
import '../providers/preferences_provider.dart';
import '../widgets/async_view.dart';
import '../widgets/reschedule_sheet.dart';
import '../widgets/status_actions.dart';
import '../widgets/status_badge.dart';
import 'calendar_provider.dart';
import 'quick_book_sheet.dart';
import 'schedule_calendar.dart';

/// Whose visits the calendar shows. RLS has already limited the rows; this
/// narrows them to what the app is for.
enum CalendarScope {
  /// The signed-in doctor's own visits, shaded by their own hours.
  doctor,

  /// Everyone's at the clinic, with a doctor filter (front desk, admin).
  clinic,

  /// The signed-in patient's own visits.
  patient,
}

/// The visits as a month, a week or a day, like a wall calendar.
///
/// With [canBook], tapping empty time books it (for staff). A visit opens
/// with [onOpenAppointment], or — without one, as at the front desk, which
/// has no appointment page — in a sheet with the day's actions.
class AppointmentCalendarScreen extends ConsumerStatefulWidget {
  const AppointmentCalendarScreen({
    super.key,
    required this.scope,
    this.canBook = false,
    this.onOpenAppointment,
    this.onOpenPatient,
    this.onBookAsPatient,
    this.title = const Text('Calendar'),
  });

  final CalendarScope scope;
  final bool canBook;
  final void Function(Appointment)? onOpenAppointment;

  /// From the visit sheet, when [onOpenAppointment] is null.
  final void Function(String patientId)? onOpenPatient;

  /// The patient app's "Book" button.
  final VoidCallback? onBookAsPatient;
  final Widget title;

  @override
  ConsumerState<AppointmentCalendarScreen> createState() => _AppointmentCalendarScreenState();
}

class _AppointmentCalendarScreenState extends ConsumerState<AppointmentCalendarScreen> {
  DateTime _date = DateUtils.dateOnly(DateTime.now());
  CalendarView? _view;

  /// Clinic scope: one doctor's visits, or (null) everyone's.
  String? _doctorId;
  bool _showCancelled = false;

  /// The last page shown, kept on screen while the next one loads.
  List<Appointment> _last = const [];

  @override
  void initState() {
    super.initState();
    // The view last picked on this device, so the front desk that works in
    // Day by doctor does not start from Week every morning.
    final saved = ref
        .read(preferencesProvider)
        .calendarView(ref.read(appRoleProvider));
    _view = CalendarView.values.where((v) => v.name == saved).firstOrNull;
  }

  CalendarView _defaultView(double width) {
    if (widget.scope == CalendarScope.patient) return CalendarView.month;
    return width >= Breakpoints.twoPane ? CalendarView.week : CalendarView.day;
  }

  void _go(CalendarView view, DateTime date) => setState(() {
        _view = view;
        _date = DateUtils.dateOnly(date);
      });

  /// Month / week / day picked: remembered. Opening a day from the week or
  /// month is a look, not a choice, so it is not.
  void _pick(CalendarView view) {
    ref
        .read(preferencesProvider)
        .setCalendarView(ref.read(appRoleProvider), view.name);
    _go(view, _date);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final view = _view ?? _defaultView(width);
    final range = calendarRangeFor(view, _date);
    final async = ref.watch(calendarAppointmentsProvider(range));
    if (async.hasValue) _last = async.requireValue;

    final allDoctors = ref.watch(doctorsProvider).value ?? const <Doctor>[];
    final me = ref.watch(currentDoctorProvider).value;
    final mine = ref.watch(myPatientProvider).value;
    final timeOff = ref.watch(timeOffProvider).value ?? const [];

    final List<Doctor> inView;
    bool keep(Appointment a) => _showCancelled || a.status.holdsTime;
    final List<Appointment> shown;
    switch (widget.scope) {
      case CalendarScope.doctor:
        inView = me == null ? const [] : [me];
        shown = [for (final a in _last) if (a.doctor.id == me?.id && keep(a)) a];
      case CalendarScope.clinic:
        inView = _doctorId == null
            ? allDoctors
            : [for (final d in allDoctors) if (d.id == _doctorId) d];
        shown = [
          for (final a in _last)
            if ((_doctorId == null || a.doctor.id == _doctorId) && keep(a)) a,
        ];
      case CalendarScope.patient:
        inView = const [];
        shown = [for (final a in _last) if (a.patient.id == mine?.id && keep(a)) a];
    }

    return Scaffold(
      appBar: AppBar(
        title: widget.title,
        actions: [
          IconButton(
            tooltip: _showCancelled ? 'Hide cancelled' : 'Show cancelled',
            isSelected: _showCancelled,
            icon: const Icon(Icons.event_busy_outlined),
            selectedIcon: const Icon(Icons.event_busy),
            onPressed: () => setState(() => _showCancelled = !_showCancelled),
          ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(widget.scope == CalendarScope.clinic ? 104 : 56),
          child: Column(
            children: [
              _Toolbar(
                view: view,
                date: _date,
                compact: width < Breakpoints.medium,
                onView: _pick,
                onDate: (d) => _go(view, d),
              ),
              if (widget.scope == CalendarScope.clinic)
                _DoctorFilter(
                  doctors: allDoctors,
                  selected: _doctorId,
                  onSelected: (id) => setState(() => _doctorId = id),
                ),
            ],
          ),
        ),
      ),
      floatingActionButton: _fab(inView),
      body: Column(
        children: [
          SizedBox(
            height: 2,
            child: async.isLoading ? const LinearProgressIndicator(minHeight: 2) : null,
          ),
          Expanded(
            child: async.hasError && !async.hasValue
                ? AsyncView<List<Appointment>>(
                    value: async,
                    onRetry: () => ref.invalidate(calendarAppointmentsProvider(range)),
                    builder: (_) => const SizedBox.shrink(),
                  )
                : ScheduleCalendar(
                    view: view,
                    date: _date,
                    appointments: shown,
                    doctors: inView,
                    timeOff: timeOff,
                    splitByDoctor: widget.scope == CalendarScope.clinic && _doctorId == null,
                    blockTitle: widget.scope == CalendarScope.patient
                        ? (a) => a.service
                        : null,
                    onOpen: _open,
                    onCreate: widget.canBook ? (start, d) => _create(start, d, inView) : null,
                    onDayTap: (day) => _go(CalendarView.day, day),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
            child: Align(alignment: Alignment.centerLeft, child: const CalendarLegend()),
          ),
        ],
      ),
    );
  }

  Widget? _fab(List<Doctor> inView) {
    if (widget.canBook) {
      void add() {
        // The next quarter hour, on the page's day if it is still to come.
        final now = DateTime.now();
        final base = _date.isAfter(now) ? DateTime(_date.year, _date.month, _date.day, 9) : now;
        final next = DateTime(base.year, base.month, base.day, base.hour,
            (base.minute ~/ 15 + (base == now ? 1 : 0)) * 15);
        showQuickBookSheet(context,
            start: next, doctor: inView.length == 1 ? inView.single : null);
      }

      // Small on a phone, where the wide one would cover a column of visits.
      if (MediaQuery.sizeOf(context).width < Breakpoints.medium) {
        return FloatingActionButton(
          tooltip: 'New appointment',
          onPressed: add,
          child: const Icon(Icons.add),
        );
      }
      return FloatingActionButton.extended(
        onPressed: add,
        icon: const Icon(Icons.add),
        label: const Text('New appointment'),
      );
    }
    if (widget.onBookAsPatient != null) {
      return FloatingActionButton.extended(
        onPressed: widget.onBookAsPatient,
        icon: const Icon(Icons.add),
        label: const Text('Book'),
      );
    }
    return null;
  }

  Future<void> _open(Appointment a) async {
    final open = widget.onOpenAppointment;
    if (open != null) {
      open(a);
      return;
    }
    final action = await showModalBottomSheet<_VisitAction>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _VisitSheet(appointment: a, canOpenPatient: widget.onOpenPatient != null),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case _VisitAction.confirm:
        await changeAppointmentStatus(context, ref, a, AppointmentStatus.confirmed,
            done: 'Confirmed');
      case _VisitAction.checkIn:
        await changeAppointmentStatus(context, ref, a, AppointmentStatus.arrived,
            done: '${a.patient.name} checked in');
      case _VisitAction.move:
        await showRescheduleSheet(context, a, staff: true);
      case _VisitAction.patient:
        widget.onOpenPatient?.call(a.patient.id);
      case _VisitAction.cancel:
        await confirmAndCancelAppointment(context, ref, a, who: a.patient.name);
    }
  }

  void _create(DateTime start, Doctor? doctor, List<Doctor> inView) {
    if (!start.isAfter(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('That time has passed. Pick a time still to come.'),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    showQuickBookSheet(context,
        start: start, doctor: doctor ?? (inView.length == 1 ? inView.single : null));
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.view,
    required this.date,
    required this.compact,
    required this.onView,
    required this.onDate,
  });

  final CalendarView view;
  final DateTime date;
  final bool compact;
  final ValueChanged<CalendarView> onView;
  final ValueChanged<DateTime> onDate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = DateUtils.dateOnly(DateTime.now());
    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            if (compact)
              IconButton(
                tooltip: 'Today',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.today),
                onPressed: () => onDate(today),
              )
            else
              OutlinedButton(
                onPressed: () => onDate(today),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                child: const Text('Today'),
              ),
            IconButton(
              tooltip: 'Previous ${view.label.toLowerCase()}',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.chevron_left),
              onPressed: () => onDate(shiftCalendar(view, date, -1)),
            ),
            IconButton(
              tooltip: 'Next ${view.label.toLowerCase()}',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.chevron_right),
              onPressed: () => onDate(shiftCalendar(view, date, 1)),
            ),
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: date,
                    firstDate: DateTime(today.year - 5),
                    lastDate: DateTime(today.year + 2),
                  );
                  if (picked != null) onDate(picked);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  child: Text(
                    compact
                        ? switch (view) {
                            CalendarView.day => DateFormat('EEE d MMM').format(date),
                            CalendarView.week => DateFormat('MMM y').format(startOfWeek(date)),
                            CalendarView.month => DateFormat('MMM y').format(date),
                          }
                        : calendarTitle(view, date),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
            if (compact)
              PopupMenuButton<CalendarView>(
                tooltip: 'View',
                initialValue: view,
                onSelected: onView,
                itemBuilder: (_) => [
                  for (final v in CalendarView.values)
                    PopupMenuItem(
                      value: v,
                      child: Row(
                        children: [
                          Icon(v.icon, size: 20),
                          const SizedBox(width: 12),
                          Text(v.label),
                        ],
                      ),
                    ),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(view.label, style: theme.textTheme.labelLarge),
                      const Icon(Icons.arrow_drop_down),
                    ],
                  ),
                ),
              )
            else
              SegmentedButton<CalendarView>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: [
                  for (final v in CalendarView.values)
                    ButtonSegment(value: v, label: Text(v.label)),
                ],
                selected: {view},
                onSelectionChanged: (s) => onView(s.first),
              ),
          ],
        ),
      ),
    );
  }
}

class _DoctorFilter extends StatelessWidget {
  const _DoctorFilter({required this.doctors, required this.selected, required this.onSelected});

  final List<Doctor> doctors;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: [
          ChoiceChip(
            label: const Text('All doctors'),
            selected: selected == null,
            onSelected: (_) => onSelected(null),
          ),
          for (final d in doctors) ...[
            const SizedBox(width: 8),
            ChoiceChip(
              label: Text('Dr. ${d.name}'),
              selected: selected == d.id,
              onSelected: (_) => onSelected(selected == d.id ? null : d.id),
            ),
          ],
        ],
      ),
    );
  }
}

enum _VisitAction { confirm, checkIn, move, patient, cancel }

/// A visit tapped on the front desk's calendar: who, when, and the steps the
/// desk takes with it. Pops with the step chosen; the screen takes it, since
/// this sheet is gone by then.
class _VisitSheet extends StatelessWidget {
  const _VisitSheet({required this.appointment, required this.canOpenPatient});

  final Appointment appointment;
  final bool canOpenPatient;

  @override
  Widget build(BuildContext context) {
    final a = appointment;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    void pick(_VisitAction action) => Navigator.pop(context, action);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(a.patient.name,
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              ),
              StatusBadge(status: a.status),
            ],
          ),
          const SizedBox(height: 8),
          _line(cs, Icons.schedule,
              '${DateFormat('EEE, MMM d · h:mm').format(a.dateTime)} – ${DateFormat('h:mm a').format(a.endsAt)}'),
          _line(cs, Icons.medical_services_outlined, a.service),
          _line(cs, Icons.person_outline, 'Dr. ${a.doctor.name}'),
          if (a.patient.phone.isNotEmpty) _line(cs, Icons.phone_outlined, a.patient.phone),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (a.status == AppointmentStatus.pending)
                FilledButton.icon(
                  onPressed: () => pick(_VisitAction.confirm),
                  icon: const Icon(Icons.check),
                  label: const Text('Confirm'),
                ),
              if (a.status == AppointmentStatus.confirmed && a.isToday)
                FilledButton.icon(
                  onPressed: () => pick(_VisitAction.checkIn),
                  icon: const Icon(Icons.how_to_reg),
                  label: const Text('Check in'),
                ),
              if (a.canReschedule)
                OutlinedButton.icon(
                  onPressed: () => pick(_VisitAction.move),
                  icon: const Icon(Icons.edit_calendar_outlined),
                  label: const Text('Move'),
                ),
              if (canOpenPatient)
                OutlinedButton.icon(
                  onPressed: () => pick(_VisitAction.patient),
                  icon: const Icon(Icons.folder_shared_outlined),
                  label: const Text('Patient'),
                ),
              if (a.status.staffCanCancel)
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: cs.error),
                  onPressed: () => pick(_VisitAction.cancel),
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('Cancel'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _line(ColorScheme cs, IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          children: [
            Icon(icon, size: 18, color: cs.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(child: Text(text)),
          ],
        ),
      );
}
