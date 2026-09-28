import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../app/adaptive_layout.dart';
import '../models/appointment.dart';
import '../models/appointment_status.dart';
import '../models/dental_chart.dart';
import '../models/patient.dart';
import '../providers/clinical_provider.dart';
import '../providers/dental_provider.dart';
import '../providers/preferences_provider.dart';
import '../providers/supabase_providers.dart';
import '../theme/tone.dart';
import 'async_view.dart';

// ── The odontogram ──────────────────────────────────────────────────────────

/// Both arches of one dentition, drawn as the dentist faces the patient: the
/// patient's right on the left of the screen, upper arch on top.
///
/// Each tooth is the classic five-surface diagram — the centre square is the
/// occlusal (or incisal) surface, the four sides are buccal on the outside of
/// the arch, lingual on the inside, mesial toward the midline, distal away
/// from it — coloured by what is on each surface now. A badge under the tooth
/// names whole-tooth work (crown, root canal, implant…), a dot marks planned
/// work, and a missing tooth is crossed out.
class Odontogram extends StatelessWidget {
  const Odontogram({
    super.key,
    required this.chart,
    required this.dentition,
    required this.numbering,
    this.selectedTooth,
    this.highlighted = const {},
    this.onToothTap,
  });

  final DentalChart chart;
  final Dentition dentition;
  final ToothNumbering numbering;
  final int? selectedTooth;

  /// Teeth to pick out, e.g. those touched at the visit being viewed.
  final Set<int> highlighted;
  final void Function(int tooth)? onToothTap;

  static const _midline = 10.0;
  static const _minTooth = 26.0;
  static const _maxTooth = 52.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final perArch = dentition.upper.length;
      final available = constraints.maxWidth - _midline;
      final size = (available / perArch).clamp(_minTooth, _maxTooth);
      final width = size * perArch + _midline;
      final arches = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _arch(context, dentition.upper, size, upper: true),
          Container(
            width: width,
            height: 1,
            margin: const EdgeInsets.symmetric(vertical: 4),
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          _arch(context, dentition.lower, size, upper: false),
        ],
      );
      // Too narrow for even the smallest teeth: scroll rather than squash.
      if (width > constraints.maxWidth) {
        return SingleChildScrollView(
            scrollDirection: Axis.horizontal, child: arches);
      }
      return Center(child: arches);
    });
  }

  Widget _arch(BuildContext context, List<int> teeth, double size,
      {required bool upper}) {
    final half = teeth.length ~/ 2;
    Widget tooth(int t) => _ToothCell(
          state: chart.stateOf(t),
          size: size,
          upper: upper,
          label: numbering.label(t),
          selected: t == selectedTooth,
          highlighted: highlighted.contains(t),
          onTap: onToothTap == null ? null : () => onToothTap!(t),
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final t in teeth.take(half)) tooth(t),
        Container(
          width: _midline,
          alignment: Alignment.center,
          child: Container(
            width: 1,
            height: size * 1.9,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        for (final t in teeth.skip(half)) tooth(t),
      ],
    );
  }
}

class _ToothCell extends StatelessWidget {
  const _ToothCell({
    required this.state,
    required this.size,
    required this.upper,
    required this.label,
    required this.selected,
    required this.highlighted,
    this.onTap,
  });

  final ToothState state;
  final double size;
  final bool upper;
  final String label;
  final bool selected;
  final bool highlighted;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final headline = state.headline;
    final number = SizedBox(
      height: 16,
      child: Text(label,
          style: TextStyle(
            fontSize: size < 32 ? 9 : 10,
            fontWeight: selected ? FontWeight.bold : FontWeight.w500,
            color: selected ? cs.primary : cs.onSurfaceVariant,
          )),
    );
    final badge = SizedBox(
      height: 14,
      child: headline == null || headline == DentalCode.missing
          ? null
          : FittedBox(
              child: Text(headline.abbreviation,
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: headline.color.readableIn(context))),
            ),
    );
    final painted = CustomPaint(
      size: Size.square(size - 4),
      painter: _ToothPainter(
        state: state,
        upper: upper,
        outline: selected ? cs.primary : cs.outline,
        empty: highlighted ? cs.primaryContainer : cs.surface,
        strokeWidth: selected ? 2 : 1,
      ),
    );

    return Semantics(
      button: onTap != null,
      selected: selected,
      label: 'Tooth $label, ${toothName(state.tooth)}. ${describeTooth(state)}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: size,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: upper
                ? [number, painted, badge]
                : [badge, painted, number],
          ),
        ),
      ),
    );
  }
}

/// `Filling on MO; crown; 1 planned`. What a screen reader says for a tooth.
String describeTooth(ToothState t) {
  if (t.isEmpty) return 'Nothing recorded';
  final parts = <String>[
    if (t.missing) 'missing',
    for (final c in t.whole) c.label.toLowerCase(),
  ];
  final bySurface = <DentalCode, List<ToothSurface>>{};
  t.surfaces.forEach((s, c) => bySurface.putIfAbsent(c, () => []).add(s));
  bySurface.forEach((c, ss) =>
      parts.add('${c.label.toLowerCase()} on ${surfacesLabel(ss)}'));
  if (t.planned.isNotEmpty) parts.add('${t.planned.length} planned');
  return parts.isEmpty ? 'Healthy' : parts.join('; ');
}

class _ToothPainter extends CustomPainter {
  _ToothPainter({
    required this.state,
    required this.upper,
    required this.outline,
    required this.empty,
    required this.strokeWidth,
  });

  final ToothState state;
  final bool upper;
  final Color outline;
  final Color empty;
  final double strokeWidth;

  /// Which drawn side is which surface. Buccal is always the outside of the
  /// arch; mesial always faces the midline, which is on the right for the
  /// patient's right-hand quadrants (1, 4, 5, 8) as drawn.
  Map<String, ToothSurface> get _sides {
    final q = state.tooth ~/ 10;
    final patientsRight = q == 1 || q == 4 || q == 5 || q == 8;
    return {
      'top': upper ? ToothSurface.buccal : ToothSurface.lingual,
      'bottom': upper ? ToothSurface.lingual : ToothSurface.buccal,
      'left': patientsRight ? ToothSurface.distal : ToothSurface.mesial,
      'right': patientsRight ? ToothSurface.mesial : ToothSurface.distal,
    };
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final inset = w * 0.3;
    final outer = Rect.fromLTWH(0, 0, w, h).deflate(strokeWidth / 2);
    final inner = Rect.fromLTRB(inset, inset, w - inset, h - inset);
    final sides = _sides;

    final polygons = <ToothSurface, Path>{
      sides['top']!: _quad(outer.topLeft, outer.topRight, inner.topRight,
          inner.topLeft),
      sides['bottom']!: _quad(outer.bottomLeft, outer.bottomRight,
          inner.bottomRight, inner.bottomLeft),
      sides['left']!: _quad(outer.topLeft, inner.topLeft, inner.bottomLeft,
          outer.bottomLeft),
      sides['right']!: _quad(outer.topRight, inner.topRight,
          inner.bottomRight, outer.bottomRight),
      ToothSurface.occlusal: Path()..addRect(inner),
    };

    final wholeFill = _wholeFill();
    for (final entry in polygons.entries) {
      final code = state.surfaces[entry.key];
      final color = state.missing
          ? empty.withAlpha(90)
          : code != null
              ? code.color.withAlpha(code.isCondition ? 200 : 170)
              : wholeFill ?? empty;
      canvas.drawPath(entry.value, Paint()..color = color);
    }

    final stroke = Paint()
      ..color = state.missing ? outline.withAlpha(90) : outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    for (final path in polygons.values) {
      canvas.drawPath(path, stroke);
    }

    // A crown caps the whole tooth: a heavy ring in the crown's colour.
    if (state.whole.contains(DentalCode.crown)) {
      canvas.drawRect(
        outer.deflate(1),
        Paint()
          ..color = DentalCode.crown.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(2.5, w * 0.08),
      );
    }

    // A root canal: a line down the middle, the way it shows on a film.
    if (state.whole.contains(DentalCode.rootCanal)) {
      final x = w / 2;
      canvas.drawLine(
        Offset(x, upper ? inner.top : 0),
        Offset(x, upper ? h : inner.bottom),
        Paint()
          ..color = DentalCode.rootCanal.color
          ..strokeWidth = math.max(2, w * 0.07),
      );
    }

    if (state.missing) {
      final x = Paint()
        ..color = DentalCode.missing.color
        ..strokeWidth = math.max(1.5, w * 0.06)
        ..strokeCap = StrokeCap.round;
      canvas
        ..drawLine(outer.topLeft + const Offset(3, 3),
            outer.bottomRight - const Offset(3, 3), x)
        ..drawLine(outer.topRight + const Offset(-3, 3),
            outer.bottomLeft + const Offset(3, -3), x);
    }

    // Work still to do: a dot in the corner, in the colour of what is next.
    if (state.planned.isNotEmpty) {
      final r = math.max(3.0, w * 0.12);
      final c = Offset(w - r * 0.6, r * 0.6);
      canvas
        ..drawCircle(c, r + 1, Paint()..color = empty)
        ..drawCircle(c, r, Paint()..color = state.planned.last.code.color)
        ..drawCircle(
            c,
            r,
            Paint()
              ..color = Colors.white
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1);
    }
  }

  /// A tint for the whole tooth when something covers all of it.
  Color? _wholeFill() {
    for (final c in const [
      DentalCode.implant,
      DentalCode.crown,
      DentalCode.bridge,
      DentalCode.impacted,
      DentalCode.fracture,
      DentalCode.caries,
      DentalCode.veneer,
      DentalCode.watch,
    ]) {
      if (state.whole.contains(c)) return c.color.withAlpha(70);
    }
    return null;
  }

  static Path _quad(Offset a, Offset b, Offset c, Offset d) => Path()
    ..moveTo(a.dx, a.dy)
    ..lineTo(b.dx, b.dy)
    ..lineTo(c.dx, c.dy)
    ..lineTo(d.dx, d.dy)
    ..close();

  @override
  bool shouldRepaint(_ToothPainter old) =>
      old.state != state ||
      old.upper != upper ||
      old.outline != outline ||
      old.empty != empty ||
      old.strokeWidth != strokeWidth;
}

/// What the colours mean. Only the codes on this chart, so it stays short.
class DentalChartLegend extends StatelessWidget {
  const DentalChartLegend({super.key, required this.chart});

  final DentalChart chart;

  @override
  Widget build(BuildContext context) {
    final used = <DentalCode>{
      for (final e in chart.entries)
        if (e.status != DentalEntryStatus.planned) e.code,
    };
    final cs = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      children: [
        for (final c in DentalCode.values)
          if (used.contains(c))
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: c.color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 4),
                Text(c.label,
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
              ],
            ),
        if (chart.plan.isNotEmpty)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.circle, size: 10, color: cs.tertiary),
              const SizedBox(width: 4),
              Text('Planned',
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
            ],
          ),
      ],
    );
  }
}

// ── The chart on a patient's record ─────────────────────────────────────────

/// The dental chart section of a patient's record or of a visit.
///
/// Renders nothing unless the current clinic charts teeth. Doctors and admins
/// tap a tooth to chart it; everyone else taps to read what is on it. With an
/// [appointment], teeth touched at that visit are highlighted, what was
/// recorded there is listed, and work can be charted as done at it once the
/// patient has arrived.
class DentalChartSection extends ConsumerStatefulWidget {
  const DentalChartSection({
    super.key,
    required this.patient,
    this.appointment,
  });

  final Patient patient;
  final Appointment? appointment;

  @override
  ConsumerState<DentalChartSection> createState() => _DentalChartSectionState();
}

class _DentalChartSectionState extends ConsumerState<DentalChartSection> {
  Dentition? _dentition;

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(clinicChartsTeethProvider)) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final patientId = widget.patient.id;
    final chartAsync = ref.watch(dentalChartProvider(patientId));
    final numbering = ref.watch(toothNumberingProvider);
    final canChart = ref.watch(canSeeClinicalNotesProvider).value ?? false;
    final appointment = widget.appointment;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
        ),
        child: AsyncView(
          value: chartAsync,
          onRetry: () => ref.invalidate(dentalEntriesProvider(patientId)),
          builder: (chart) {
            final dentition = _dentition ??
                (chart.hasPermanentTeeth
                    ? Dentition.permanent
                    : chart.hasPrimaryTeeth
                        ? Dentition.primary
                        : Dentition.forAge(widget.patient.age));
            final atVisit = appointment == null
                ? const <DentalEntry>[]
                : chart.atVisit(appointment.id);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.grid_view_rounded,
                        size: 16, color: cs.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Text('Dental chart',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: cs.onSurfaceVariant,
                            fontSize: 12)),
                    const Spacer(),
                    _ChartOptions(
                      dentition: dentition,
                      onDentition: (d) => setState(() => _dentition = d),
                    ),
                  ],
                ),
                Text(
                  canChart
                      ? 'Tap a tooth to chart it.'
                      : 'Tap a tooth to see its history.',
                  style: TextStyle(fontSize: 11, color: cs.outline),
                ),
                const SizedBox(height: 12),
                Odontogram(
                  chart: chart,
                  dentition: dentition,
                  numbering: numbering,
                  highlighted: {for (final e in atVisit) e.tooth},
                  onToothTap: (t) => showToothSheet(
                    context,
                    patient: widget.patient,
                    tooth: t,
                    appointment: appointment,
                  ),
                ),
                const SizedBox(height: 12),
                DentalChartLegend(chart: chart),
                if (appointment != null) ...[
                  const SizedBox(height: 16),
                  _SubHeading('At this visit'),
                  if (atVisit.isEmpty)
                    Text(
                        canChart
                            ? 'Nothing charted yet. Tap the teeth you examine or treat.'
                            : 'Nothing charted at this visit.',
                        style: TextStyle(fontSize: 13, color: cs.outline))
                  else
                    for (final e in atVisit)
                      DentalEntryTile(
                        entry: e,
                        numbering: numbering,
                        onTap: () => showToothSheet(context,
                            patient: widget.patient,
                            tooth: e.tooth,
                            appointment: appointment),
                      ),
                ],
                if (chart.plan.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _SubHeading('Treatment plan'),
                  for (final e in chart.plan)
                    DentalEntryTile(
                      entry: e,
                      numbering: numbering,
                      trailing: canChart && _attended(appointment)
                          ? _MarkDoneButton(
                              entry: e,
                              patientId: patientId,
                              appointmentId: appointment!.id,
                            )
                          : null,
                      onTap: () => showToothSheet(context,
                          patient: widget.patient,
                          tooth: e.tooth,
                          appointment: appointment),
                    ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Work can be charted as done only at a visit the patient came to. Mirrors
/// the database's rule.
bool _attended(Appointment? a) =>
    a != null &&
    (a.status == AppointmentStatus.arrived ||
        a.status == AppointmentStatus.inConsultation ||
        a.status == AppointmentStatus.completed);

class _SubHeading extends StatelessWidget {
  const _SubHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      );
}

/// Adult/child teeth, and FDI/Universal numbering (remembered on this device).
class _ChartOptions extends ConsumerWidget {
  const _ChartOptions({required this.dentition, required this.onDentition});

  final Dentition dentition;
  final ValueChanged<Dentition> onDentition;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final numbering = ref.watch(toothNumberingProvider);
    return PopupMenuButton<Object>(
      tooltip: 'Chart options',
      icon: const Icon(Icons.tune, size: 20),
      onSelected: (v) {
        if (v is Dentition) onDentition(v);
        if (v is ToothNumbering) {
          ref.read(toothNumberingProvider.notifier).set(v);
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(enabled: false, child: Text('Teeth')),
        for (final d in Dentition.values)
          CheckedPopupMenuItem(
              value: d, checked: d == dentition, child: Text(d.label)),
        const PopupMenuDivider(),
        const PopupMenuItem(enabled: false, child: Text('Numbering')),
        for (final n in ToothNumbering.values)
          CheckedPopupMenuItem(
              value: n, checked: n == numbering, child: Text(n.displayName)),
      ],
    );
  }
}

/// One line of the chart: `Filling 46 · MO`, its status, and its note.
class DentalEntryTile extends StatelessWidget {
  const DentalEntryTile({
    super.key,
    required this.entry,
    required this.numbering,
    this.trailing,
    this.onTap,
    this.forPatient = false,
  });

  final DentalEntry entry;
  final ToothNumbering numbering;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool forPatient;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final e = entry;
    final note = e.note;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      visualDensity: VisualDensity.compact,
      onTap: onTap,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: e.code.color.withAlpha(40),
        child: Icon(e.code.icon,
            size: 16, color: e.code.color.readableIn(context)),
      ),
      title: Text(e.describe(numbering, forPatient: forPatient),
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        [
          forPatient ? toothName(e.tooth) : _statusText(e),
          if (note != null && !forPatient) note,
        ].join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: cs.onSurfaceVariant),
      ),
      trailing: trailing,
    );
  }

  static String _statusText(DentalEntry e) {
    final date = e.createdAt == null
        ? ''
        : ' ${DateFormat('MMM d, y').format(e.createdAt!)}';
    return switch (e.status) {
      DentalEntryStatus.existing =>
        e.code.isCondition ? 'Found$date' : 'Already present$date',
      DentalEntryStatus.planned => 'Planned$date',
      DentalEntryStatus.done => 'Done$date',
    };
  }
}

class _MarkDoneButton extends ConsumerStatefulWidget {
  const _MarkDoneButton({
    required this.entry,
    required this.patientId,
    required this.appointmentId,
  });

  final DentalEntry entry;
  final String patientId;
  final String appointmentId;

  @override
  ConsumerState<_MarkDoneButton> createState() => _MarkDoneButtonState();
}

class _MarkDoneButtonState extends ConsumerState<_MarkDoneButton> {
  bool _busy = false;

  Future<void> _done() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(healthRepositoryProvider)
          .completeDentalEntry(widget.entry.id, widget.appointmentId);
      ref.invalidate(dentalEntriesProvider(widget.patientId));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text(describeError(e)),
          behavior: SnackBarBehavior.floating));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: _busy ? null : _done,
        child: _busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Text('Done today'),
      );
}

// ── One tooth ───────────────────────────────────────────────────────────────

/// Everything about one tooth, and — for a doctor or admin — the form to chart
/// something new on it.
Future<void> showToothSheet(
  BuildContext context, {
  required Patient patient,
  required int tooth,
  Appointment? appointment,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ToothSheet(
          patient: patient, tooth: tooth, appointment: appointment),
    );

class _ToothSheet extends ConsumerStatefulWidget {
  const _ToothSheet({
    required this.patient,
    required this.tooth,
    this.appointment,
  });

  final Patient patient;
  final int tooth;
  final Appointment? appointment;

  @override
  ConsumerState<_ToothSheet> createState() => _ToothSheetState();
}

class _ToothSheetState extends ConsumerState<_ToothSheet> {
  bool _adding = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final numbering = ref.watch(toothNumberingProvider);
    final canChart = ref.watch(canSeeClinicalNotesProvider).value ?? false;
    final chart = ref.watch(dentalChartProvider(widget.patient.id)).value;
    final state = chart?.stateOf(widget.tooth) ?? ToothState(widget.tooth);
    final history = state.history.reversed.toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: _adding ? 0.9 : 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: EdgeInsets.fromLTRB(
            20, 0, 20, 24 + MediaQuery.of(context).viewInsets.bottom),
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(numbering.label(widget.tooth),
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: cs.onPrimaryContainer)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(toothName(widget.tooth),
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    Text(describeTooth(state),
                        style: TextStyle(color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (canChart && !_adding)
            FilledButton.tonalIcon(
              onPressed: () => setState(() => _adding = true),
              icon: const Icon(Icons.add),
              label: const Text('Chart this tooth'),
            ),
          if (_adding)
            _EntryForm(
              patient: widget.patient,
              tooth: widget.tooth,
              appointment: widget.appointment,
              onDone: () => setState(() => _adding = false),
            ),
          const SizedBox(height: 16),
          Text('History', style: theme.textTheme.titleSmall),
          if (history.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('Nothing recorded on this tooth.',
                  style: TextStyle(color: cs.outline)),
            )
          else
            for (final e in history)
              DentalEntryTile(
                entry: e,
                numbering: numbering,
                trailing: canChart
                    ? _EntryMenu(
                        entry: e,
                        patientId: widget.patient.id,
                        appointment: widget.appointment,
                      )
                    : null,
              ),
        ],
      ),
    );
  }
}

class _EntryMenu extends ConsumerWidget {
  const _EntryMenu({
    required this.entry,
    required this.patientId,
    this.appointment,
  });

  final DentalEntry entry;
  final String patientId;
  final Appointment? appointment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visit = appointment;
    final canComplete =
        entry.status == DentalEntryStatus.planned && _attended(visit);
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 20),
      onSelected: (action) async {
        final messenger = ScaffoldMessenger.of(context);
        final repo = ref.read(healthRepositoryProvider);
        try {
          if (action == 'done') {
            await repo.completeDentalEntry(entry.id, visit!.id);
          } else if (action == 'delete') {
            final sure = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Remove this entry?'),
                content: const Text(
                    'Use this for something charted by mistake. It is removed '
                    'from the chart for everyone.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Keep')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Remove')),
                ],
              ),
            );
            if (sure != true) return;
            await repo.deleteDentalEntry(entry.id);
          }
          ref.invalidate(dentalEntriesProvider(patientId));
        } catch (e) {
          messenger.showSnackBar(SnackBar(
              content: Text(describeError(e)),
              behavior: SnackBarBehavior.floating));
        }
      },
      itemBuilder: (_) => [
        if (canComplete)
          const PopupMenuItem(value: 'done', child: Text('Done at this visit')),
        const PopupMenuItem(value: 'delete', child: Text('Remove')),
      ],
    );
  }
}

/// Chart one thing on one tooth: what, where on it, and whether it was found,
/// is planned, or was done today.
class _EntryForm extends ConsumerStatefulWidget {
  const _EntryForm({
    required this.patient,
    required this.tooth,
    required this.onDone,
    this.appointment,
  });

  final Patient patient;
  final int tooth;
  final Appointment? appointment;
  final VoidCallback onDone;

  @override
  ConsumerState<_EntryForm> createState() => _EntryFormState();
}

class _EntryFormState extends ConsumerState<_EntryForm> {
  DentalCode? _code;
  DentalEntryStatus? _status;
  final _surfaces = <ToothSurface>{};
  final _note = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  List<DentalEntryStatus> get _statuses {
    final code = _code;
    if (code == null) return const [];
    return [
      for (final s in code.allowedStatuses)
        if (s != DentalEntryStatus.done || _attended(widget.appointment)) s,
    ];
  }

  void _pick(DentalCode code) => setState(() {
        _code = code;
        _error = null;
        if (!code.usesSurfaces) _surfaces.clear();
        final allowed = _statuses;
        if (!allowed.contains(_status)) {
          // At a visit the patient came to, treatment is most often what was
          // just done; anywhere else, what is planned.
          _status = allowed.contains(DentalEntryStatus.done)
              ? DentalEntryStatus.done
              : allowed.contains(DentalEntryStatus.planned)
                  ? DentalEntryStatus.planned
                  : allowed.first;
        }
      });

  bool get _valid =>
      _code != null &&
      _status != null &&
      (!_code!.usesSurfaces ||
          _surfaces.isNotEmpty ||
          _code!.isCondition ||
          _code == DentalCode.veneer);

  Future<void> _save() async {
    final code = _code, status = _status;
    if (code == null || status == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(healthRepositoryProvider).addDentalEntry(
            clinicId: widget.patient.clinicId,
            patientId: widget.patient.id,
            tooth: widget.tooth,
            code: code,
            status: status,
            surfaces: code.usesSurfaces ? _surfaces : const {},
            appointmentId: widget.appointment?.id,
            note: _note.text,
          );
      ref.invalidate(dentalEntriesProvider(widget.patient.id));
      widget.onDone();
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final code = _code;

    Widget chips(Iterable<DentalCode> codes) => Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final c in codes)
              ChoiceChip(
                avatar: Icon(c.icon,
                    size: 16, color: c.color.readableIn(context)),
                label: Text(c.label),
                selected: c == code,
                onSelected: (_) => _pick(c),
              ),
          ],
        );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Found', style: TextStyle(fontSize: 12, color: cs.outline)),
          const SizedBox(height: 4),
          chips(DentalCode.values.where((c) => c.isCondition)),
          const SizedBox(height: 12),
          Text('Treatment', style: TextStyle(fontSize: 12, color: cs.outline)),
          const SizedBox(height: 4),
          chips(DentalCode.values.where((c) => !c.isCondition)),
          if (code != null && code.usesSurfaces) ...[
            const SizedBox(height: 12),
            Text('Surfaces', style: TextStyle(fontSize: 12, color: cs.outline)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              children: [
                for (final s in ToothSurface.values)
                  FilterChip(
                    label: Text('${s.wire} · ${s.labelFor(widget.tooth)}'),
                    selected: _surfaces.contains(s),
                    onSelected: (on) => setState(
                        () => on ? _surfaces.add(s) : _surfaces.remove(s)),
                  ),
              ],
            ),
          ],
          if (code != null && _statuses.length > 1) ...[
            const SizedBox(height: 12),
            SegmentedButton<DentalEntryStatus>(
              segments: [
                for (final s in _statuses)
                  ButtonSegment(
                    value: s,
                    label: Text(switch (s) {
                      DentalEntryStatus.existing => 'Already there',
                      DentalEntryStatus.planned => 'Plan it',
                      DentalEntryStatus.done => 'Done today',
                    }),
                  ),
              ],
              selected: {if (_status != null) _status!},
              onSelectionChanged: (s) => setState(() => _status = s.first),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            maxLength: 500,
            maxLines: 2,
            minLines: 1,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Detail, e.g. composite, shade A2 (staff only)',
              counterText: '',
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: TextStyle(color: cs.error)),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : widget.onDone,
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: _busy || !_valid ? null : _save,
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Save'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── For the patient ─────────────────────────────────────────────────────────

/// What happened to the patient's teeth at one visit, in plain words: what was
/// done, what was found, what is planned next. Renders nothing when nothing
/// was charted or the clinic does not chart teeth.
class VisitDentalSummary extends ConsumerWidget {
  const VisitDentalSummary({
    super.key,
    required this.patientId,
    required this.appointmentId,
    this.forPatient = false,
  });

  final String patientId;
  final String appointmentId;
  final bool forPatient;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(clinicChartsTeethProvider)) return const SizedBox.shrink();
    final chart = ref.watch(dentalChartProvider(patientId)).value;
    if (chart == null) return const SizedBox.shrink();
    final entries = chart.atVisit(appointmentId);
    if (entries.isEmpty) return const SizedBox.shrink();
    final numbering = ref.watch(toothNumberingProvider);
    final cs = Theme.of(context).colorScheme;

    List<DentalEntry> having(DentalEntryStatus s) =>
        [for (final e in entries) if (e.status == s) e];
    final groups = [
      (forPatient ? 'Treatment you received' : 'Done', having(DentalEntryStatus.done)),
      (forPatient ? 'What the dentist found' : 'Found', having(DentalEntryStatus.existing)),
      (forPatient ? 'Recommended next' : 'Planned', having(DentalEntryStatus.planned)),
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.grid_view_rounded, size: 16, color: cs.primary),
                const SizedBox(width: 6),
                Text('Your teeth at this visit',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant)),
              ],
            ),
            for (final (title, list) in groups)
              if (list.isNotEmpty) ...[
                const SizedBox(height: 10),
                _SubHeading(title),
                for (final e in list)
                  DentalEntryTile(
                      entry: e, numbering: numbering, forPatient: forPatient),
              ],
          ],
        ),
      ),
    );
  }
}

/// A patient's whole chart, read-only: the teeth, and the plan in words.
class MyDentalChartScreen extends ConsumerStatefulWidget {
  const MyDentalChartScreen({super.key, required this.patient});

  final Patient patient;

  @override
  ConsumerState<MyDentalChartScreen> createState() =>
      _MyDentalChartScreenState();
}

class _MyDentalChartScreenState extends ConsumerState<MyDentalChartScreen> {
  int? _selected;
  Dentition? _dentition;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final patientId = widget.patient.id;
    final numbering = ref.watch(toothNumberingProvider);
    final chartAsync = ref.watch(dentalChartProvider(patientId));

    return Scaffold(
      appBar: AppBar(title: const Text('My teeth')),
      body: AsyncView(
        value: chartAsync,
        onRetry: () => ref.invalidate(dentalEntriesProvider(patientId)),
        builder: (chart) {
          final dentition = _dentition ??
              (chart.hasPermanentTeeth || !chart.hasPrimaryTeeth
                  ? Dentition.forAge(widget.patient.age)
                  : Dentition.primary);
          final selected = _selected;
          final tooth = selected == null ? null : chart.stateOf(selected);
          return RefreshIndicator(
            onRefresh: () => ref.refresh(dentalEntriesProvider(patientId).future),
            child: CenteredScroll(
              maxWidth: ContentWidth.detail,
              padding: const EdgeInsets.all(16),
              builder: (padding) => ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: padding,
                children: [
                  if (chart.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        'Your dentist has not charted your teeth yet. After your '
                        'next check-up, what they find and do will show here.',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SegmentedButton<Dentition>(
                              showSelectedIcon: false,
                              segments: [
                                for (final d in Dentition.values)
                                  ButtonSegment(
                                      value: d, label: Text('${d.label} teeth')),
                              ],
                              selected: {dentition},
                              onSelectionChanged: (s) => setState(() {
                                _dentition = s.first;
                                _selected = null;
                              }),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text('Your right',
                            style: TextStyle(fontSize: 10, color: cs.outline)),
                        Odontogram(
                          chart: chart,
                          dentition: dentition,
                          numbering: numbering,
                          selectedTooth: selected,
                          onToothTap: (t) => setState(
                              () => _selected = _selected == t ? null : t),
                        ),
                        const SizedBox(height: 12),
                        DentalChartLegend(chart: chart),
                      ],
                    ),
                  ),
                  if (tooth != null) ...[
                    const SizedBox(height: 16),
                    Text(toothName(tooth.tooth),
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    if (tooth.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('Nothing recorded on this tooth.',
                            style: TextStyle(color: cs.outline)),
                      )
                    else
                      for (final e in tooth.history.reversed)
                        DentalEntryTile(
                            entry: e, numbering: numbering, forPatient: true),
                  ],
                  if (chart.plan.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text('Recommended treatment',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    Text('What your dentist has planned. Ask the clinic to book it.',
                        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                    for (final e in chart.plan)
                      DentalEntryTile(
                          entry: e, numbering: numbering, forPatient: true),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// `Filling 46 MO · Sealant 36 O`: a visit's dental work on one line, for a
/// row in a list of visits.
class VisitDentalLine extends ConsumerWidget {
  const VisitDentalLine({
    super.key,
    required this.patientId,
    required this.appointmentId,
  });

  final String patientId;
  final String appointmentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(clinicChartsTeethProvider)) return const SizedBox.shrink();
    final chart = ref.watch(dentalChartProvider(patientId)).value;
    if (chart == null) return const SizedBox.shrink();
    final entries = chart.atVisit(appointmentId);
    if (entries.isEmpty) return const SizedBox.shrink();
    final numbering = ref.watch(toothNumberingProvider);
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final e in entries)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: e.code.color.withAlpha(30),
                borderRadius: BorderRadius.circular(6),
                border: e.status == DentalEntryStatus.planned
                    ? Border.all(color: e.code.color.withAlpha(120))
                    : null,
              ),
              child: Text(
                '${e.code.abbreviation} ${numbering.label(e.tooth)}'
                '${e.surfaces.isEmpty ? '' : ' ${surfacesLabel(e.surfaces)}'}',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface),
              ),
            ),
        ],
      ),
    );
  }
}
