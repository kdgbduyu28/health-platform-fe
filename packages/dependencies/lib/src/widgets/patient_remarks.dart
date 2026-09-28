import 'package:flutter/material.dart';

import '../models/appointment.dart';
import '../models/appointment_status.dart';
import '../models/invoice.dart';
import '../models/patient.dart';

/// A remark's colour, readable on the card behind it in either theme.
Color remarkColor(BuildContext context, PatientFlag flag) {
  final base = switch (flag) {
    PatientFlag.recall => Colors.indigo,
    PatientFlag.balance => Colors.orange.shade800,
    PatientFlag.noContact => Colors.blueGrey,
    PatientFlag.attention => Colors.red.shade700,
    PatientFlag.pedia => Colors.teal,
    PatientFlag.adult => Colors.grey.shade700,
  };
  final dark = Theme.of(context).brightness == Brightness.dark;
  return dark ? Color.lerp(base, Colors.white, 0.45)! : base;
}

/// One remark on a patient, as a small tinted label. [attention] explains a
/// "Needs attention" in its tooltip.
class RemarkChip extends StatelessWidget {
  const RemarkChip({
    super.key,
    required this.flag,
    this.attention = const {},
    this.dense = false,
  });

  final PatientFlag flag;
  final Set<AttentionReason> attention;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final color = remarkColor(context, flag);
    final chip = Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 6 : 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(28),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(70)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(flag.icon, size: dense ? 12 : 14, color: color),
          const SizedBox(width: 4),
          Text(flag.label,
              style: TextStyle(
                  fontSize: dense ? 11 : 12,
                  fontWeight: FontWeight.w600,
                  color: color)),
        ],
      ),
    );
    if (flag != PatientFlag.attention || attention.isEmpty) return chip;
    return Tooltip(
      message: [for (final r in attention) r.label].join('\n'),
      child: chip,
    );
  }
}

/// Every remark on a patient, action ones first, the age group last.
class RemarkChips extends StatelessWidget {
  const RemarkChips({
    super.key,
    required this.flags,
    this.attention = const {},
    this.dense = false,
    this.showAgeGroup = true,
  });

  final Set<PatientFlag> flags;
  final Set<AttentionReason> attention;
  final bool dense;
  final bool showAgeGroup;

  @override
  Widget build(BuildContext context) {
    final shown = [
      for (final f in PatientFlag.values)
        if (flags.contains(f) && (showAgeGroup || !f.isAgeGroup)) f,
    ];
    if (shown.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final f in shown)
          RemarkChip(flag: f, attention: attention, dense: dense),
      ],
    );
  }
}

/// The remarks on one chart, worked out from what the patient page has
/// already loaded. Mirrors `public.search_patients`, so the page and the list
/// agree.
({Set<PatientFlag> flags, Set<AttentionReason> attention}) patientRemarks({
  required Patient patient,
  required List<Appointment> visits,
  required List<Invoice> invoices,
  required int plannedCount,
  required int recallMonths,
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  final completed = [
    for (final a in visits)
      if (a.status == AppointmentStatus.completed) a.dateTime,
  ]..sort();
  final lastVisit = completed.isEmpty ? null : completed.last;
  final hasNext = visits.any((a) =>
      a.dateTime.isAfter(at) &&
      a.status != AppointmentStatus.cancelled &&
      a.status != AppointmentStatus.noShow);
  final over = [
    for (final a in visits)
      if (!a.dateTime.isAfter(at) &&
          (a.status == AppointmentStatus.completed ||
              a.status == AppointmentStatus.noShow))
        a,
  ]..sort((a, b) => b.dateTime.compareTo(a.dateTime));
  final owed = [
    for (final v in invoices)
      if (v.status == InvoiceStatus.issued && v.balance > 0) v,
  ];
  final age = patient.age;

  final attention = {
    if (plannedCount > 0 && !hasNext) AttentionReason.unbookedPlan,
    if (over.isNotEmpty && over.first.status == AppointmentStatus.noShow)
      AttentionReason.noShow,
    if (owed.any((v) => (v.issuedAt ?? v.createdAt)
        .isBefore(at.subtract(const Duration(days: 30)))))
      AttentionReason.overdueBalance,
  };
  final recallBefore = DateTime(at.year, at.month - recallMonths, at.day,
      at.hour, at.minute);

  return (
    flags: {
      if (lastVisit != null && lastVisit.isBefore(recallBefore) && !hasNext)
        PatientFlag.recall,
      if (owed.isNotEmpty) PatientFlag.balance,
      if (patient.phone.trim().isEmpty && patient.email.trim().isEmpty)
        PatientFlag.noContact,
      if (attention.isNotEmpty) PatientFlag.attention,
      if (age != null) age < 18 ? PatientFlag.pedia : PatientFlag.adult,
    },
    attention: attention,
  );
}
