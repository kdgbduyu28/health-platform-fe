import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/appointment.dart';
import '../models/appointment_status.dart';
import '../models/doctor.dart';
import '../models/time_off.dart';
import '../theme/tone.dart';
import 'calendar_provider.dart';

/// How much of the calendar one page shows.
enum CalendarView {
  month('Month', Icons.calendar_view_month),
  week('Week', Icons.calendar_view_week),
  day('Day', Icons.calendar_view_day);

  const CalendarView(this.label, this.icon);

  final String label;
  final IconData icon;
}

// ── Dates ────────────────────────────────────────────────────────────────────
// Days are built with the DateTime constructor rather than by adding
// Durations, so a daylight-saving change never shifts a day by an hour.

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime _addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

/// The Monday on or before [d]. Weeks run Monday to Sunday, as the
/// doctors' working days (1=Mon … 7=Sun) do.
DateTime startOfWeek(DateTime d) => _addDays(d, 1 - d.weekday);

/// The days a page of [view] around [date] covers. A month page is the six
/// whole weeks that hold it, so its first and last rows show the edges of the
/// months either side.
CalendarRange calendarRangeFor(CalendarView view, DateTime date) {
  switch (view) {
    case CalendarView.month:
      final from = startOfWeek(DateTime(date.year, date.month));
      return (from: from, to: _addDays(from, 42));
    case CalendarView.week:
      final from = startOfWeek(date);
      return (from: from, to: _addDays(from, 7));
    case CalendarView.day:
      final from = _day(date);
      return (from: from, to: _addDays(from, 1));
  }
}

/// The page before or after the one around [date].
DateTime shiftCalendar(CalendarView view, DateTime date, int by) =>
    switch (view) {
      CalendarView.month => DateTime(date.year, date.month + by, 1),
      CalendarView.week => _addDays(date, 7 * by),
      CalendarView.day => _addDays(date, by),
    };

/// `September 2026`, `Sep 21 – 27, 2026`, `Wed, Sep 23, 2026`.
String calendarTitle(CalendarView view, DateTime date) {
  switch (view) {
    case CalendarView.month:
      return DateFormat('MMMM y').format(date);
    case CalendarView.week:
      final r = calendarRangeFor(view, date);
      final last = _addDays(r.to, -1);
      if (r.from.year != last.year) {
        return '${DateFormat('MMM d, y').format(r.from)} – '
            '${DateFormat('MMM d, y').format(last)}';
      }
      if (r.from.month != last.month) {
        return '${DateFormat('MMM d').format(r.from)} – '
            '${DateFormat('MMM d, y').format(last)}';
      }
      return '${DateFormat('MMM d').format(r.from)} – '
          '${DateFormat('d, y').format(last)}';
    case CalendarView.day:
      return DateFormat('EEE, MMM d, y').format(date);
  }
}

// ── Working hours and time off ───────────────────────────────────────────────

/// A stretch of one day, in minutes since midnight: [start, end).
typedef MinuteSpan = ({int start, int end});

/// The clinic-wide closure covering [day], if any.
TimeOff? closureOn(List<TimeOff> timeOff, DateTime day) {
  final d = _day(day);
  for (final t in timeOff) {
    if (t.isClosure && !d.isBefore(_day(t.startsOn)) && !d.isAfter(_day(t.endsOn))) {
      return t;
    }
  }
  return null;
}

/// [doctor]'s own leave covering [day], if any.
TimeOff? leaveOn(List<TimeOff> timeOff, Doctor doctor, DateTime day) {
  final d = _day(day);
  for (final t in timeOff) {
    if (t.doctorId == doctor.id &&
        !d.isBefore(_day(t.startsOn)) &&
        !d.isAfter(_day(t.endsOn))) {
      return t;
    }
  }
  return null;
}

/// When [doctor] takes patients on [day]: each start time in their list
/// opens the gap to the next one (or one step, for the last), merged into
/// spans. Empty on a day off, on leave, or when the clinic is closed.
List<MinuteSpan> workingSpans(Doctor doctor, DateTime day, List<TimeOff> timeOff) {
  if (!doctor.availableWeekdays.contains(day.weekday)) return const [];
  if (closureOn(timeOff, day) != null || leaveOn(timeOff, doctor, day) != null) {
    return const [];
  }
  final starts = [
    for (final s in doctor.availableTimeSlots)
      if (parseClock(s) case final m?) m,
  ]..sort();
  if (starts.isEmpty) return const [];
  final step = workingHoursOf(doctor.availableTimeSlots)?.step ?? 30;
  return mergeSpans([for (final m in starts) (start: m, end: math.min(m + step, 24 * 60))]);
}

/// [spans] sorted and joined wherever they touch or overlap.
List<MinuteSpan> mergeSpans(Iterable<MinuteSpan> spans) {
  final sorted = [...spans]..sort((a, b) => a.start.compareTo(b.start));
  final out = <MinuteSpan>[];
  for (final s in sorted) {
    if (out.isNotEmpty && s.start <= out.last.end) {
      final last = out.removeLast();
      out.add((start: last.start, end: math.max(last.end, s.end)));
    } else {
      out.add(s);
    }
  }
  return out;
}

// ── Overlapping visits side by side ─────────────────────────────────────────

/// Where each visit sits across its column: [lane] of [lanes] equal strips.
/// Visits that overlap, directly or through a chain, share a group and split
/// its width, as in any calendar. The database refuses a doctor or patient
/// in two places at once, so this happens only across doctors or patients,
/// or with cancelled visits shown.
typedef LanePlace = ({int lane, int lanes});

Map<String, LanePlace> layoutLanes(List<Appointment> items) {
  final sorted = [...items]
    ..sort((a, b) {
      final c = a.dateTime.compareTo(b.dateTime);
      return c != 0 ? c : b.endsAt.compareTo(a.endsAt);
    });
  final out = <String, LanePlace>{};
  var group = <Appointment>[];
  var laneEnds = <DateTime>[];
  final laneOf = <String, int>{};
  DateTime? groupEnd;

  void flush() {
    for (final a in group) {
      out[a.id] = (lane: laneOf[a.id]!, lanes: laneEnds.length);
    }
    group = [];
    laneEnds = [];
  }

  for (final a in sorted) {
    if (groupEnd != null && !a.dateTime.isBefore(groupEnd)) flush();
    var lane = laneEnds.indexWhere((end) => !a.dateTime.isBefore(end));
    if (lane == -1) {
      lane = laneEnds.length;
      laneEnds.add(a.endsAt);
    } else {
      laneEnds[lane] = a.endsAt;
    }
    laneOf[a.id] = lane;
    group.add(a);
    groupEnd = group.length == 1 || a.endsAt.isAfter(groupEnd!) ? a.endsAt : groupEnd;
  }
  flush();
  return out;
}

// ── The calendar ─────────────────────────────────────────────────────────────

/// A page of visits laid out like a wall calendar: a month grid, or a week or
/// day of hours with each visit a block as long as it lasts.
///
/// It only draws; the screen around it owns the page ([view], [date]) and
/// decides what the callbacks do. Without [onCreate], empty time is not
/// tappable.
class ScheduleCalendar extends StatelessWidget {
  const ScheduleCalendar({
    super.key,
    required this.view,
    required this.date,
    required this.appointments,
    this.doctors = const [],
    this.timeOff = const [],
    this.splitByDoctor = false,
    this.blockTitle,
    this.onOpen,
    this.onCreate,
    this.onDayTap,
  });

  final CalendarView view;
  final DateTime date;
  final List<Appointment> appointments;

  /// The doctors in view. Their hours leave the rest of the day shaded, and
  /// with [splitByDoctor] the day view gives each a column. Empty: no
  /// shading.
  final List<Doctor> doctors;

  /// Closures shade whole days; a doctor's leave shades their column.
  final List<TimeOff> timeOff;

  /// Day view only: one column per doctor, side by side.
  final bool splitByDoctor;

  /// What a block says first. Defaults to the patient's name.
  final String Function(Appointment)? blockTitle;

  final void Function(Appointment)? onOpen;

  /// Empty time tapped: its start, snapped to the quarter hour, and the
  /// doctor whose column it was, if the columns are doctors'.
  final void Function(DateTime start, Doctor? doctor)? onCreate;

  /// A day's number (month) or heading (week) tapped.
  final void Function(DateTime day)? onDayTap;

  String _title(Appointment a) => blockTitle?.call(a) ?? a.patient.name;

  @override
  Widget build(BuildContext context) {
    if (view == CalendarView.month) {
      return _MonthGrid(
        date: date,
        appointments: appointments,
        timeOff: timeOff,
        title: _title,
        onOpen: onOpen,
        onDayTap: onDayTap,
      );
    }
    return _TimeGrid(
      key: ValueKey((view, _day(date), splitByDoctor)),
      columns: _columns(),
      title: _title,
      onOpen: onOpen,
      onCreate: onCreate,
      onDayTap: view == CalendarView.week ? onDayTap : null,
    );
  }

  List<_GridColumn> _columns() {
    List<Appointment> on(DateTime day) => [
          for (final a in appointments)
            if (DateUtils.isSameDay(a.dateTime, day)) a,
        ];

    if (view == CalendarView.week) {
      final r = calendarRangeFor(view, date);
      return [
        for (var i = 0; i < 7; i++)
          () {
            final day = _addDays(r.from, i);
            final closure = closureOn(timeOff, day);
            return _GridColumn(
              day: day,
              items: on(day),
              open: doctors.isEmpty
                  ? null
                  : mergeSpans([for (final d in doctors) ...workingSpans(d, day, timeOff)]),
              blocked: closure != null ? _closedLabel(closure) : null,
            );
          }(),
      ];
    }

    final day = _day(date);
    final closure = closureOn(timeOff, day);
    final items = on(day);
    if (!splitByDoctor || doctors.length < 2) {
      final one = doctors.length == 1 ? doctors.single : null;
      final leave = one == null ? null : leaveOn(timeOff, one, day);
      return [
        _GridColumn(
          day: day,
          doctor: one,
          items: items,
          open: doctors.isEmpty
              ? null
              : mergeSpans([for (final d in doctors) ...workingSpans(d, day, timeOff)]),
          blocked: closure != null
              ? _closedLabel(closure)
              : leave != null
                  ? _leaveLabel(leave)
                  : null,
        ),
      ];
    }

    final ids = {for (final d in doctors) d.id};
    final others = [for (final a in items) if (!ids.contains(a.doctor.id)) a];
    return [
      for (final d in doctors)
        () {
          final leave = leaveOn(timeOff, d, day);
          return _GridColumn(
            day: day,
            doctor: d,
            items: [for (final a in items) if (a.doctor.id == d.id) a],
            open: workingSpans(d, day, timeOff),
            blocked: closure != null
                ? _closedLabel(closure)
                : leave != null
                    ? _leaveLabel(leave)
                    : null,
          );
        }(),
      // Visits with a doctor no longer on the roster still show.
      if (others.isNotEmpty) _GridColumn(day: day, items: others, heading: 'Other'),
    ];
  }
}

String _closedLabel(TimeOff t) =>
    t.reason == null || t.reason!.trim().isEmpty ? 'Clinic closed' : 'Closed · ${t.reason}';

String _leaveLabel(TimeOff t) =>
    t.reason == null || t.reason!.trim().isEmpty ? 'On leave' : 'On leave · ${t.reason}';

class _GridColumn {
  const _GridColumn({
    required this.day,
    required this.items,
    this.doctor,
    this.open,
    this.blocked,
    this.heading,
  });

  final DateTime day;
  final Doctor? doctor;
  final List<Appointment> items;

  /// Bookable time; the rest is shaded. Null: nothing is shaded.
  final List<MinuteSpan>? open;

  /// Why the whole column is shaded (a closure, leave), if it is.
  final String? blocked;
  final String? heading;
}

// ── Week and day: hours down the side ───────────────────────────────────────

const double _hourHeight = 60;
const double _minuteHeight = _hourHeight / 60;
const double _gutter = 56;
const double _minColumnWidth = 112;
const int _snapMinutes = 15;

class _TimeGrid extends StatefulWidget {
  const _TimeGrid({
    super.key,
    required this.columns,
    required this.title,
    this.onOpen,
    this.onCreate,
    this.onDayTap,
  });

  final List<_GridColumn> columns;
  final String Function(Appointment) title;
  final void Function(Appointment)? onOpen;
  final void Function(DateTime start, Doctor? doctor)? onCreate;
  final void Function(DateTime day)? onDayTap;

  @override
  State<_TimeGrid> createState() => _TimeGridState();
}

class _TimeGridState extends State<_TimeGrid> {
  late final ScrollController _vertical =
      ScrollController(initialScrollOffset: _firstOffset());
  final _horizontal = ScrollController();
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    // Keeps the red "now" line moving.
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _vertical.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  /// Opens on the working day rather than at midnight: an hour before the
  /// earliest of the first open time, the first visit, and — today — now.
  double _firstOffset() {
    var minute = 8 * 60;
    final starts = <int>[
      for (final c in widget.columns) ...[
        if (c.open != null && c.open!.isNotEmpty) c.open!.first.start,
        for (final a in c.items) a.dateTime.hour * 60 + a.dateTime.minute,
      ],
    ];
    if (starts.isNotEmpty) minute = starts.reduce(math.min);
    final now = DateTime.now();
    if (widget.columns.any((c) => DateUtils.isSameDay(c.day, now))) {
      minute = math.min(minute, now.hour * 60 + now.minute);
    }
    return math.max(0, (minute - 60) * _minuteHeight);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (context, box) {
      final n = widget.columns.length;
      final fits = box.maxWidth - _gutter >= n * _minColumnWidth || n == 1;
      final columnWidth = fits
          ? (box.maxWidth - _gutter) / n
          : _minColumnWidth;
      final gridWidth = _gutter + columnWidth * n;

      final grid = SizedBox(
        width: fits ? box.maxWidth : gridWidth,
        child: Column(
          children: [
            _header(context, columnWidth),
            Divider(height: 1, color: cs.outlineVariant),
            Expanded(
              child: SingleChildScrollView(
                controller: _vertical,
                child: SizedBox(
                  height: 24 * _hourHeight,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _HourGutter(),
                      for (final c in widget.columns)
                        SizedBox(
                          width: columnWidth,
                          child: _DayColumn(
                            key: ValueKey('calendar-column-'
                                '${c.doctor?.id ?? c.heading ?? c.day.toIso8601String()}'),
                            column: c,
                            title: widget.title,
                            onOpen: widget.onOpen,
                            onCreate: widget.onCreate,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
      if (fits) return grid;
      return Scrollbar(
        controller: _horizontal,
        child: SingleChildScrollView(
          controller: _horizontal,
          scrollDirection: Axis.horizontal,
          child: grid,
        ),
      );
    });
  }

  Widget _header(BuildContext context, double columnWidth) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final today = DateTime.now();
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          const SizedBox(width: _gutter),
          for (final c in widget.columns)
            SizedBox(
              width: columnWidth,
              child: c.doctor != null || c.heading != null
                  ? _DoctorHeading(doctor: c.doctor, heading: c.heading, count: c.items.length)
                  : InkWell(
                      onTap: widget.onDayTap == null ? null : () => widget.onDayTap!(c.day),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            DateFormat('EEE').format(c.day).toUpperCase(),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: DateUtils.isSameDay(c.day, today)
                                  ? cs.primary
                                  : cs.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 2),
                          _DayNumber(day: c.day, today: DateUtils.isSameDay(c.day, today)),
                        ],
                      ),
                    ),
            ),
        ],
      ),
    );
  }
}

class _DoctorHeading extends StatelessWidget {
  const _DoctorHeading({this.doctor, this.heading, required this.count});

  final Doctor? doctor;
  final String? heading;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final name = doctor == null ? heading! : 'Dr. ${doctor!.name}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: cs.primaryContainer,
            child: Text(
              doctor?.initials ?? '?',
              style: TextStyle(fontSize: 11, color: cs.onPrimaryContainer),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge),
                Text(
                  '$count visit${count == 1 ? '' : 's'}',
                  style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DayNumber extends StatelessWidget {
  const _DayNumber({required this.day, required this.today, this.muted = false});

  final DateTime day;
  final bool today;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: today ? BoxDecoration(color: cs.primary, shape: BoxShape.circle) : null,
      child: Text(
        '${day.day}',
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: today
              ? cs.onPrimary
              : muted
                  ? cs.outline
                  : cs.onSurface,
        ),
      ),
    );
  }
}

class _HourGutter extends StatelessWidget {
  const _HourGutter();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return SizedBox(
      width: _gutter,
      child: Stack(
        children: [
          for (var h = 1; h < 24; h++)
            Positioned(
              top: h * _hourHeight - 7,
              right: 8,
              child: Text(DateFormat('h a').format(DateTime(2000, 1, 1, h)), style: style),
            ),
        ],
      ),
    );
  }
}

/// One day's (or one doctor's) hours: shading, hour lines, the visits, the
/// "now" line, and — when booking is allowed — a hint of the quarter hour
/// under the pointer.
class _DayColumn extends StatefulWidget {
  const _DayColumn({
    super.key,
    required this.column,
    required this.title,
    this.onOpen,
    this.onCreate,
  });

  final _GridColumn column;
  final String Function(Appointment) title;
  final void Function(Appointment)? onOpen;
  final void Function(DateTime start, Doctor? doctor)? onCreate;

  @override
  State<_DayColumn> createState() => _DayColumnState();
}

class _DayColumnState extends State<_DayColumn> {
  /// The quarter hour under the mouse, for the "+ 10:15" hint.
  int? _hover;

  int _snap(double dy) {
    final m = (dy / _minuteHeight).floor();
    return (m ~/ _snapMinutes * _snapMinutes).clamp(0, 24 * 60 - _snapMinutes);
  }

  DateTime _at(int minute) {
    final d = widget.column.day;
    return DateTime(d.year, d.month, d.day, minute ~/ 60, minute % 60);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = widget.column;
    final canCreate = widget.onCreate != null;
    final lanes = layoutLanes(c.items);
    final now = DateTime.now();

    return LayoutBuilder(builder: (context, box) {
      final width = box.maxWidth;
      return MouseRegion(
        cursor: canCreate ? SystemMouseCursors.click : MouseCursor.defer,
        onHover: canCreate ? (e) => setState(() => _hover = _snap(e.localPosition.dy)) : null,
        onExit: canCreate ? (_) => setState(() => _hover = null) : null,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: canCreate
              ? (e) => widget.onCreate!(_at(_snap(e.localPosition.dy)), c.doctor)
              : null,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _ColumnPainter(
                    open: c.blocked != null ? const [] : c.open,
                    past: DateUtils.isSameDay(c.day, now)
                        ? now.hour * 60 + now.minute
                        : c.day.isBefore(_day(now))
                            ? 24 * 60
                            : 0,
                    line: cs.outlineVariant,
                    shade: cs.onSurface.withAlpha(26),
                    pastShade: cs.onSurface.withAlpha(8),
                  ),
                ),
              ),
              if (c.blocked != null)
                Positioned(
                  top: 8,
                  left: 4,
                  right: 4,
                  child: _BlockedLabel(text: c.blocked!),
                ),
              if (_hover != null && canCreate)
                Positioned(
                  top: _hover! * _minuteHeight,
                  left: 2,
                  right: 2,
                  height: 30 * _minuteHeight,
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      alignment: Alignment.centerLeft,
                      decoration: BoxDecoration(
                        color: cs.primary.withAlpha(20),
                        border: Border.all(color: cs.primary.withAlpha(120)),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '+ ${DateFormat('h:mm a').format(_at(_hover!))}',
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        style: TextStyle(fontSize: 11, color: cs.primary),
                      ),
                    ),
                  ),
                ),
              for (final a in c.items)
                () {
                  final place = lanes[a.id]!;
                  final top = (a.dateTime.hour * 60 + a.dateTime.minute) * _minuteHeight;
                  final bottom = math.min(
                    24 * _hourHeight,
                    top + a.durationMinutes * _minuteHeight,
                  );
                  final laneWidth = (width - 6) / place.lanes;
                  return Positioned(
                    top: top + 1,
                    height: math.max(20, bottom - top - 2),
                    left: 2 + place.lane * laneWidth,
                    width: laneWidth - 2,
                    child: AppointmentBlock(
                      appointment: a,
                      title: widget.title(a),
                      onTap: widget.onOpen == null ? null : () => widget.onOpen!(a),
                    ),
                  );
                }(),
              if (DateUtils.isSameDay(c.day, now))
                Positioned(
                  top: (now.hour * 60 + now.minute) * _minuteHeight - 1,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(child: _NowLine(color: cs.error)),
                ),
            ],
          ),
        ),
      );
    });
  }
}

class _BlockedLabel extends StatelessWidget {
  const _BlockedLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Icon(Icons.event_busy, size: 14, color: cs.onSurfaceVariant),
            const SizedBox(width: 4),
            Expanded(
              child: Text(text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
            ),
          ],
        ),
      ),
    );
  }
}

class _NowLine extends StatelessWidget {
  const _NowLine({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        Expanded(child: Container(height: 2, color: color)),
      ],
    );
  }
}

class _ColumnPainter extends CustomPainter {
  _ColumnPainter({
    required this.open,
    required this.past,
    required this.line,
    required this.shade,
    required this.pastShade,
  });

  /// Bookable spans; null means shade nothing.
  final List<MinuteSpan>? open;

  /// Minutes of the day already gone.
  final int past;
  final Color line;
  final Color shade;
  final Color pastShade;

  @override
  void paint(Canvas canvas, Size size) {
    final open = this.open;
    if (open != null) {
      final paint = Paint()..color = shade;
      var from = 0;
      for (final s in [...open, (start: 24 * 60, end: 24 * 60)]) {
        if (s.start > from) {
          canvas.drawRect(
            Rect.fromLTRB(0, from * _minuteHeight, size.width, s.start * _minuteHeight),
            paint,
          );
        }
        from = math.max(from, s.end);
      }
    }
    if (past > 0) {
      canvas.drawRect(
        Rect.fromLTRB(0, 0, size.width, past * _minuteHeight),
        Paint()..color = pastShade,
      );
    }
    final hour = Paint()
      ..color = line
      ..strokeWidth = 1;
    final half = Paint()
      ..color = line.withAlpha((line.a * 255).round() ~/ 3)
      ..strokeWidth = 1;
    for (var h = 0; h < 24; h++) {
      final y = h * _hourHeight;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), hour);
      canvas.drawLine(Offset(0, y + _hourHeight / 2), Offset(size.width, y + _hourHeight / 2), half);
    }
    canvas.drawLine(Offset.zero, Offset(0, size.height), hour);
  }

  @override
  bool shouldRepaint(_ColumnPainter old) =>
      old.open != open || old.past != past || old.line != line || old.shade != shade;
}

/// A visit on the time grid: tinted by its status, as tall as it lasts.
class AppointmentBlock extends StatelessWidget {
  const AppointmentBlock({
    super.key,
    required this.appointment,
    required this.title,
    this.onTap,
  });

  final Appointment appointment;
  final String title;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final a = appointment;
    final cs = Theme.of(context).colorScheme;
    final color = a.status.color.readableIn(context);
    final gone = !a.status.holdsTime;
    final time = DateFormat('h:mm').format(a.dateTime);
    final end = DateFormat('h:mm a').format(a.endsAt);
    final text = TextStyle(
      fontSize: 11,
      height: 1.2,
      color: gone ? cs.onSurfaceVariant : cs.onSurface,
      decoration: gone ? TextDecoration.lineThrough : null,
    );

    return Tooltip(
      message: '$title\n$time – $end · ${a.service}\n'
          'Dr. ${a.doctor.name} · ${a.status.displayName}',
      waitDuration: const Duration(milliseconds: 500),
      child: Material(
        color: Color.alphaBlend(color.withAlpha(gone ? 18 : 46), cs.surface),
        borderRadius: BorderRadius.circular(6),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: color, width: 3)),
            ),
            padding: const EdgeInsets.fromLTRB(5, 2, 4, 2),
            child: LayoutBuilder(builder: (context, box) {
              final roomy = box.maxHeight >= 34;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    roomy ? title : '$time $title',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (roomy)
                    Flexible(
                      child: Text(
                        '$time – $end · ${a.service}',
                        maxLines: box.maxHeight >= 60 ? 3 : 1,
                        overflow: TextOverflow.ellipsis,
                        style: text,
                      ),
                    ),
                ],
              );
            }),
          ),
        ),
      ),
    );
  }
}

// ── Month ───────────────────────────────────────────────────────────────────

/// Below this width a month cell shows dots, not lines of text.
const double _roomyMonthCell = 96;

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.date,
    required this.appointments,
    required this.timeOff,
    required this.title,
    this.onOpen,
    this.onDayTap,
  });

  final DateTime date;
  final List<Appointment> appointments;
  final List<TimeOff> timeOff;
  final String Function(Appointment) title;
  final void Function(Appointment)? onOpen;
  final void Function(DateTime day)? onDayTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final range = calendarRangeFor(CalendarView.month, date);
    final byDay = <DateTime, List<Appointment>>{};
    for (final a in [...appointments]..sort((a, b) => a.dateTime.compareTo(b.dateTime))) {
      byDay.putIfAbsent(_day(a.dateTime), () => []).add(a);
    }

    return Column(
      children: [
        SizedBox(
          height: 32,
          child: Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Center(
                    child: Text(
                      DateFormat('EEE').format(_addDays(range.from, i)).toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Divider(height: 1, color: cs.outlineVariant),
        Expanded(
          child: LayoutBuilder(builder: (context, box) {
            final rowHeight = math.max(box.maxHeight / 6, 76.0);
            final roomy = box.maxWidth / 7 >= _roomyMonthCell;
            final rows = Column(
              children: [
                for (var w = 0; w < 6; w++)
                  SizedBox(
                    height: rowHeight,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < 7; i++)
                          () {
                            final day = _addDays(range.from, w * 7 + i);
                            return Expanded(
                              child: _MonthCell(
                                day: day,
                                inMonth: day.month == date.month,
                                items: byDay[day] ?? const [],
                                closure: closureOn(timeOff, day),
                                roomy: roomy,
                                height: rowHeight,
                                title: title,
                                onOpen: onOpen,
                                onTap: onDayTap == null ? null : () => onDayTap!(day),
                              ),
                            );
                          }(),
                      ],
                    ),
                  ),
              ],
            );
            if (rowHeight * 6 <= box.maxHeight + 0.5) return rows;
            return SingleChildScrollView(child: rows);
          }),
        ),
      ],
    );
  }
}

class _MonthCell extends StatelessWidget {
  const _MonthCell({
    required this.day,
    required this.inMonth,
    required this.items,
    required this.closure,
    required this.roomy,
    required this.height,
    required this.title,
    this.onOpen,
    this.onTap,
  });

  final DateTime day;
  final bool inMonth;
  final List<Appointment> items;
  final TimeOff? closure;
  final bool roomy;
  final double height;
  final String Function(Appointment) title;
  final void Function(Appointment)? onOpen;
  final VoidCallback? onTap;

  static const double _line = 18;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final today = DateUtils.isSameDay(day, DateTime.now());
    final live = [for (final a in items) if (a.status.holdsTime) a];

    Widget body;
    if (roomy) {
      final fit = math.max(0, ((height - 36) / _line).floor());
      final shown = items.length <= fit ? items : items.take(math.max(0, fit - 1)).toList();
      final more = items.length - shown.length;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (closure != null && fit > 0 && items.isEmpty)
            Text(_closedLabel(closure!),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
          for (final a in shown) _MonthChip(appointment: a, title: title(a), onTap: onOpen),
          if (more > 0)
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 1),
              child: Text('+$more more',
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
            ),
        ],
      );
    } else {
      // A phone: a dot per visit (up to four) and the count; tap for the day.
      body = Column(
        children: [
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 3,
            runSpacing: 3,
            children: [
              for (final a in live.take(4))
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(color: a.status.color.readableIn(context), shape: BoxShape.circle),
                ),
            ],
          ),
          if (live.length > 4)
            Text('+${live.length - 4}',
                style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
        ],
      );
    }

    return Material(
      color: closure != null
          ? cs.surfaceContainerHighest.withAlpha(140)
          : inMonth
              ? cs.surface
              : cs.surfaceContainerLow,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              right: BorderSide(color: cs.outlineVariant, width: 0.5),
              bottom: BorderSide(color: cs.outlineVariant, width: 0.5),
            ),
          ),
          padding: const EdgeInsets.all(2),
          child: Column(
            crossAxisAlignment: roomy ? CrossAxisAlignment.stretch : CrossAxisAlignment.center,
            children: [
              Align(
                alignment: roomy ? Alignment.topLeft : Alignment.topCenter,
                child: Semantics(
                  label: '${DateFormat('EEEE, MMMM d').format(day)}, '
                      '${live.length} visit${live.length == 1 ? '' : 's'}',
                  child: _DayNumber(day: day, today: today, muted: !inMonth),
                ),
              ),
              const SizedBox(height: 2),
              Expanded(child: ClipRect(child: body)),
            ],
          ),
        ),
      ),
    );
  }
}

class _MonthChip extends StatelessWidget {
  const _MonthChip({required this.appointment, required this.title, this.onTap});

  final Appointment appointment;
  final String title;
  final void Function(Appointment)? onTap;

  @override
  Widget build(BuildContext context) {
    final a = appointment;
    final cs = Theme.of(context).colorScheme;
    final gone = !a.status.holdsTime;
    return InkWell(
      onTap: onTap == null ? null : () => onTap!(a),
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: _MonthCell._line,
        child: Row(
          children: [
            const SizedBox(width: 2),
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: gone ? Colors.transparent : a.status.color.readableIn(context),
                border: gone ? Border.all(color: a.status.color.readableIn(context)) : null,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                '${DateFormat('h:mma').format(a.dateTime).toLowerCase()} $title',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: gone ? cs.onSurfaceVariant : cs.onSurface,
                  decoration: gone ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Status colours as a key, for the foot of the calendar.
class CalendarLegend extends StatelessWidget {
  const CalendarLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: [
        for (final s in AppointmentStatus.values)
          if (s != AppointmentStatus.noShow)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: s.color.readableIn(context), borderRadius: BorderRadius.circular(3)),
                ),
                const SizedBox(width: 4),
                Text(s.displayName, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
              ],
            ),
      ],
    );
  }
}
