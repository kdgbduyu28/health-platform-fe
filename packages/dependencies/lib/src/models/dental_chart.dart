import 'package:flutter/material.dart';

/// The dental chart (odontogram), as the database keeps it: a log of
/// [DentalEntry] rows in `dental_chart_entries`, one per thing known about one
/// tooth. What each tooth looks like today is derived from that log by
/// [DentalChart], never stored — so the picture and the history cannot
/// disagree.
///
/// Teeth are numbered FDI (ISO 3950) everywhere in data: quadrant then
/// position, 11–48 permanent, 51–85 primary. [ToothNumbering] converts for
/// display.

/// A tooth surface. On the chart, [buccal] faces the outside of the arch and
/// [mesial] faces the midline.
enum ToothSurface {
  mesial('M', 'Mesial'),
  occlusal('O', 'Occlusal'),
  distal('D', 'Distal'),
  buccal('B', 'Buccal'),
  lingual('L', 'Lingual');

  const ToothSurface(this.wire, this.label);

  final String wire;
  final String label;

  static ToothSurface fromWire(String value) =>
      values.firstWhere((s) => s.wire == value);

  /// Front teeth have an incisal edge and a facial side rather than an
  /// occlusal surface and a buccal one; same surface, the name dentists use.
  String labelFor(int tooth) => switch (this) {
        occlusal when isAnterior(tooth) => 'Incisal',
        buccal when isAnterior(tooth) => 'Facial',
        lingual when tooth ~/ 10 == 1 || tooth ~/ 10 == 2 ||
                tooth ~/ 10 == 5 || tooth ~/ 10 == 6 =>
          'Palatal',
        _ => label,
      };
}

/// What an entry records. Conditions are findings; the rest are treatments.
enum DentalCode {
  caries('caries', 'Decay', 'Car', isCondition: true, usesSurfaces: true),
  fracture('fracture', 'Fracture', 'Fx', isCondition: true, usesSurfaces: true),
  missing('missing', 'Missing', 'M', isCondition: true),
  impacted('impacted', 'Impacted', 'Imp', isCondition: true),
  watch('watch', 'Watch', 'W', isCondition: true),
  filling('filling', 'Filling', 'F', usesSurfaces: true),
  sealant('sealant', 'Sealant', 'S', usesSurfaces: true),
  veneer('veneer', 'Veneer', 'V', usesSurfaces: true),
  crown('crown', 'Crown', 'Cr'),
  bridge('bridge', 'Bridge', 'Br'),
  rootCanal('root_canal', 'Root canal', 'RCT'),
  implant('implant', 'Implant', 'Imp'),
  extraction('extraction', 'Extraction', 'X');

  const DentalCode(
    this.wire,
    this.label,
    this.abbreviation, {
    this.isCondition = false,
    this.usesSurfaces = false,
  });

  final String wire;
  final String label;
  final String abbreviation;

  /// A finding (always [DentalEntryStatus.existing]), not a treatment.
  final bool isCondition;

  /// Recorded on particular surfaces rather than the whole tooth.
  final bool usesSurfaces;

  static DentalCode fromWire(String value) =>
      values.firstWhere((c) => c.wire == value);

  /// The statuses the database accepts for this code.
  List<DentalEntryStatus> get allowedStatuses => isCondition
      ? const [DentalEntryStatus.existing]
      : this == extraction
          ? const [DentalEntryStatus.planned, DentalEntryStatus.done]
          : DentalEntryStatus.values;

  /// The chart colour: problems warm, restorations cool, gone grey.
  Color get color => switch (this) {
        caries => const Color(0xFFD32F2F),
        fracture => const Color(0xFFE64A19),
        missing || extraction => const Color(0xFF757575),
        impacted => const Color(0xFF8D6E63),
        watch => const Color(0xFFF9A825),
        filling => const Color(0xFF1E88E5),
        sealant => const Color(0xFF00897B),
        veneer => const Color(0xFF5E35B1),
        crown => const Color(0xFFC49000),
        bridge => const Color(0xFF6D4C41),
        rootCanal => const Color(0xFFAD1457),
        implant => const Color(0xFF455A64),
      };

  IconData get icon => switch (this) {
        caries => Icons.coronavirus_outlined,
        fracture => Icons.flash_on_outlined,
        missing => Icons.remove_circle_outline,
        impacted => Icons.vertical_align_bottom,
        watch => Icons.visibility_outlined,
        filling => Icons.format_color_fill,
        sealant => Icons.shield_outlined,
        veneer => Icons.layers_outlined,
        crown => Icons.emoji_events_outlined,
        bridge => Icons.linear_scale,
        rootCanal => Icons.timeline,
        implant => Icons.hardware_outlined,
        extraction => Icons.content_cut,
      };

  /// How a patient reads it, where the clinical word would puzzle them.
  String get patientLabel => switch (this) {
        caries => 'Cavity',
        rootCanal => 'Root canal treatment',
        watch => 'Being monitored',
        _ => label,
      };
}

enum DentalEntryStatus {
  /// Found on examination: a condition, or work done before (anywhere).
  existing('existing', 'On exam'),

  /// The treatment plan: to be done at a later visit.
  planned('planned', 'Planned'),

  /// Performed at the entry's visit.
  done('done', 'Done');

  const DentalEntryStatus(this.wire, this.label);

  final String wire;
  final String label;

  static DentalEntryStatus fromWire(String value) =>
      values.firstWhere((s) => s.wire == value);
}

/// One row of `dental_chart_entries`, or of `patient_dental_chart()` — which
/// is the same row without [note].
class DentalEntry {
  const DentalEntry({
    required this.id,
    required this.tooth,
    required this.code,
    required this.status,
    this.surfaces = const {},
    this.appointmentId,
    this.note,
    this.createdAt,
    this.updatedAt,
  });

  final String id;

  /// FDI number.
  final int tooth;
  final DentalCode code;
  final DentalEntryStatus status;
  final Set<ToothSurface> surfaces;

  /// The visit it was found, planned or done at. Null for what was charted
  /// outside a visit.
  final String? appointmentId;

  /// A short technical detail. Never present for a patient: their function
  /// leaves it out.
  final String? note;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory DentalEntry.fromJson(Map<String, dynamic> json) => DentalEntry(
        id: json['id'] as String,
        tooth: json['tooth'] as int,
        code: DentalCode.fromWire(json['code'] as String),
        status: DentalEntryStatus.fromWire(json['status'] as String),
        surfaces: {
          for (final s in json['surfaces'] as List<dynamic>? ?? const [])
            ToothSurface.fromWire(s as String),
        },
        appointmentId: json['appointment_id'] as String?,
        note: json['note'] as String?,
        createdAt: _time(json['created_at']),
        updatedAt: _time(json['updated_at']),
      );

  /// `Filling 46 · MO`, in the given numbering.
  String describe(ToothNumbering numbering, {bool forPatient = false}) {
    final name = forPatient ? code.patientLabel : code.label;
    final where = surfaces.isEmpty ? '' : ' · ${surfacesLabel(surfaces)}';
    return '$name ${numbering.label(tooth)}$where';
  }
}

/// `MOD`: surfaces in the conventional order.
String surfacesLabel(Iterable<ToothSurface> surfaces) {
  final set = surfaces.toSet();
  return [for (final s in ToothSurface.values) if (set.contains(s)) s.wire]
      .join();
}

DateTime? _time(Object? value) =>
    value == null ? null : DateTime.parse(value as String).toLocal();

// ── Numbering ───────────────────────────────────────────────────────────────

/// How tooth numbers are shown. Storage is always FDI.
enum ToothNumbering {
  /// Two digits, quadrant then position: 11–48, primary 51–85.
  fdi('fdi', 'FDI'),

  /// 1–32 from the upper right around to the lower right; primary A–T.
  universal('universal', 'Universal');

  const ToothNumbering(this.wire, this.displayName);

  final String wire;
  final String displayName;

  static ToothNumbering fromWire(String? value) =>
      values.firstWhere((n) => n.wire == value, orElse: () => fdi);

  /// [fdi] tooth number as this system writes it.
  String label(int fdi) => switch (this) {
        ToothNumbering.fdi => '$fdi',
        ToothNumbering.universal => universalLabel(fdi),
      };
}

/// FDI → Universal: `18` → `1`, `48` → `32`, `55` → `A`, `85` → `T`.
String universalLabel(int fdi) {
  final q = fdi ~/ 10, p = fdi % 10;
  if (q <= 4) {
    final n = switch (q) {
      1 => 9 - p,
      2 => 8 + p,
      3 => 25 - p,
      _ => 24 + p,
    };
    return '$n';
  }
  final i = switch (q) {
    5 => 5 - p,
    6 => 4 + p,
    7 => 15 - p,
    _ => 14 + p,
  };
  return String.fromCharCode('A'.codeUnitAt(0) + i);
}

/// Incisors and canines.
bool isAnterior(int fdi) => fdi % 10 <= 3;

bool isPrimary(int fdi) => fdi ~/ 10 >= 5;

/// `Lower left first molar`.
String toothName(int fdi) {
  final q = fdi ~/ 10, p = fdi % 10;
  final jaw = (q == 1 || q == 2 || q == 5 || q == 6) ? 'Upper' : 'Lower';
  final side = (q == 1 || q == 4 || q == 5 || q == 8) ? 'right' : 'left';
  final kind = isPrimary(fdi)
      ? const ['central incisor', 'lateral incisor', 'canine', 'first molar',
          'second molar'][p - 1]
      : const ['central incisor', 'lateral incisor', 'canine',
          'first premolar', 'second premolar', 'first molar', 'second molar',
          'third molar'][p - 1];
  return '$jaw $side ${isPrimary(fdi) ? 'baby ' : ''}$kind';
}

/// The teeth of one dentition, laid out as the chart draws them: the upper
/// arch left to right as seen facing the patient (their right first), then the
/// lower arch the same way.
enum Dentition {
  permanent('Adult'),
  primary('Child');

  const Dentition(this.label);

  final String label;

  List<int> get upper => this == permanent
      ? const [18, 17, 16, 15, 14, 13, 12, 11, 21, 22, 23, 24, 25, 26, 27, 28]
      : const [55, 54, 53, 52, 51, 61, 62, 63, 64, 65];

  List<int> get lower => this == permanent
      ? const [48, 47, 46, 45, 44, 43, 42, 41, 31, 32, 33, 34, 35, 36, 37, 38]
      : const [85, 84, 83, 82, 81, 71, 72, 73, 74, 75];

  /// Children under 12 are charted on their baby teeth by default.
  static Dentition forAge(int? age) =>
      age != null && age < 12 ? primary : permanent;
}

// ── The chart ───────────────────────────────────────────────────────────────

/// One tooth as the chart shows it now.
class ToothState {
  ToothState(this.tooth);

  final int tooth;

  /// Gone: found missing or extracted, and not since replaced by an implant.
  bool missing = false;

  /// What is on each surface now: decay, or what repaired it.
  final Map<ToothSurface, DentalCode> surfaces = {};

  /// Whole-tooth findings and restorations present now.
  final Set<DentalCode> whole = {};

  /// Work still to be done on this tooth.
  final List<DentalEntry> planned = [];

  /// Everything ever recorded on this tooth, oldest first.
  final List<DentalEntry> history = [];

  bool get isEmpty => history.isEmpty;

  bool get hasProblem =>
      surfaces.values.any((c) => c.isCondition) ||
      whole.any((c) => c.isCondition && c != DentalCode.missing);

  /// The single most telling code, for a compact marker.
  DentalCode? get headline {
    if (missing) return DentalCode.missing;
    for (final c in const [
      DentalCode.implant,
      DentalCode.crown,
      DentalCode.bridge,
      DentalCode.rootCanal,
      DentalCode.impacted,
      DentalCode.fracture,
      DentalCode.caries,
      DentalCode.veneer,
      DentalCode.watch,
    ]) {
      if (whole.contains(c)) return c;
    }
    return null;
  }
}

/// A patient's chart: [DentalEntry] rows folded into a [ToothState] per tooth.
///
/// Entries apply in the order they were recorded. A later filling on a surface
/// replaces the decay under it; an extraction (or a tooth found missing)
/// clears everything on the tooth, and a later implant brings it back. Planned
/// work changes nothing until it is done.
class DentalChart {
  DentalChart(List<DentalEntry> entries) {
    final ordered = [...entries]..sort((a, b) {
        final at = a.createdAt, bt = b.createdAt;
        if (at == null || bt == null) return 0;
        return at.compareTo(bt);
      });
    for (final e in ordered) {
      final t = _teeth.putIfAbsent(e.tooth, () => ToothState(e.tooth));
      t.history.add(e);
      if (e.status == DentalEntryStatus.planned) {
        t.planned.add(e);
        continue;
      }
      _apply(t, e);
    }
    this.entries = List.unmodifiable(ordered);
  }

  final Map<int, ToothState> _teeth = {};

  /// Every entry, oldest first.
  late final List<DentalEntry> entries;

  ToothState stateOf(int tooth) => _teeth[tooth] ?? ToothState(tooth);

  bool get isEmpty => _teeth.isEmpty;

  /// Outstanding work, tooth by tooth.
  List<DentalEntry> get plan => [
        for (final t in (_teeth.values.toList()
          ..sort((a, b) => a.tooth.compareTo(b.tooth))))
          ...t.planned,
      ];

  /// What was recorded at one visit, in chart order.
  List<DentalEntry> atVisit(String appointmentId) =>
      [for (final e in entries) if (e.appointmentId == appointmentId) e]
        ..sort((a, b) => a.tooth.compareTo(b.tooth));

  /// Whether any primary tooth has been charted, so the chart can open on the
  /// dentition the patient actually has.
  bool get hasPrimaryTeeth => _teeth.keys.any(isPrimary);
  bool get hasPermanentTeeth => _teeth.keys.any((t) => !isPrimary(t));

  static void _apply(ToothState t, DentalEntry e) {
    switch (e.code) {
      case DentalCode.missing:
      case DentalCode.extraction:
        t
          ..missing = true
          ..surfaces.clear()
          ..whole.clear();
      case DentalCode.implant:
        t
          ..missing = false
          ..surfaces.clear()
          ..whole.clear()
          ..whole.add(DentalCode.implant);
      case DentalCode.crown:
        // A crown covers every surface.
        t
          ..surfaces.clear()
          ..whole.remove(DentalCode.caries)
          ..whole.remove(DentalCode.fracture)
          ..whole.add(DentalCode.crown);
      case DentalCode.caries || DentalCode.fracture
          when e.surfaces.isEmpty:
        t.whole.add(e.code);
      case DentalCode.filling ||
            DentalCode.sealant ||
            DentalCode.veneer ||
            DentalCode.caries ||
            DentalCode.fracture:
        if (e.surfaces.isEmpty) {
          t.whole.add(e.code);
        } else {
          for (final s in e.surfaces) {
            t.surfaces[s] = e.code;
          }
          // Repairing the tooth resolves whole-tooth decay recorded before.
          if (!e.code.isCondition) {
            t.whole
              ..remove(DentalCode.caries)
              ..remove(DentalCode.fracture);
          }
        }
      case DentalCode.rootCanal:
        t.whole
          ..add(DentalCode.rootCanal)
          ..remove(DentalCode.caries);
      case DentalCode.bridge ||
            DentalCode.impacted ||
            DentalCode.watch:
        t.whole.add(e.code);
    }
  }
}
