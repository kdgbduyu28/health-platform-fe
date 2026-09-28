import 'package:flutter/material.dart';

import 'patient_intake.dart';

/// A patient chart: one person's record at ONE clinic.
///
/// The database keeps identity and clinical content apart. `persons` holds who
/// someone is (name, phone, date of birth) and is shared by every clinic that
/// treats them; `patients` is the chart, and belongs to a single clinic. The
/// clinical text on a chart lives in `chart_notes`, readable only by that
/// clinic's doctors and admins — see [ClinicalNote].
///
/// The screens want one object per patient, so the person is embedded and
/// flattened here:
///
///   patients?select=*,person:persons(*)
class Patient {
  const Patient({
    required this.id,
    required this.personId,
    required this.clinicId,
    required this.name,
    required this.phone,
    required this.email,
    this.dateOfBirth,
    this.sex,
    this.address,
    this.occupation,
    this.emergencyContactName,
    this.emergencyContactPhone,
    this.hasIntake,
    this.chartNumber,
  });

  /// The chart id — what appointments point at.
  final String id;
  final String personId;
  final String clinicId;

  final String name;
  final String phone;
  final String email;
  final DateTime? dateOfBirth;
  final Sex? sex;
  final String? address;
  final String? occupation;
  final String? emergencyContactName;
  final String? emergencyContactPhone;

  /// The clinic's own record number for the chart ("A-0042"), when it keeps
  /// one: the paper folder's, or the old system's. Set by an import.
  final String? chartNumber;

  /// Whether the patient information form has been filled in for this chart.
  /// Null when the query did not ask (only [HealthRepository.fetchMyPatients]
  /// embeds it, for the patient app's first-visit gate).
  final bool? hasIntake;

  /// Nullable person columns become empty strings, because the UI treats them
  /// as plain text; a missing embed degrades the same way rather than crashing.
  factory Patient.fromJson(Map<String, dynamic> json) {
    final person =
        json['person'] as Map<String, dynamic>? ?? const <String, dynamic>{};
    return Patient(
      id: json['id'] as String,
      personId: json['person_id'] as String,
      clinicId: json['clinic_id'] as String,
      name: person['full_name'] as String? ?? '',
      phone: person['phone'] as String? ?? '',
      email: person['email'] as String? ?? '',
      dateOfBirth: person['date_of_birth'] == null
          ? null
          : DateTime.parse(person['date_of_birth'] as String),
      sex: Sex.fromWire(person['sex'] as String?),
      address: person['address'] as String?,
      occupation: person['occupation'] as String?,
      emergencyContactName: person['emergency_contact_name'] as String?,
      emergencyContactPhone: person['emergency_contact_phone'] as String?,
      chartNumber: json['chart_number'] as String?,
      // One-to-one, but PostgREST may still hand back a list for an embed
      // across a composite key.
      hasIntake: !json.containsKey('intake')
          ? null
          : switch (json['intake']) {
              null => false,
              List<dynamic> l => l.isNotEmpty,
              _ => true,
            },
    );
  }

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (name.trim().isEmpty) return '?';
    if (parts.length >= 2) return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    return parts.first[0].toUpperCase();
  }

  int? get age {
    if (dateOfBirth == null) return null;
    final now = DateTime.now();
    int a = now.year - dateOfBirth!.year;
    if (now.month < dateOfBirth!.month ||
        (now.month == dateOfBirth!.month && now.day < dateOfBirth!.day)) {
      a--;
    }
    return a;
  }

  /// Whether this patient is what someone typed into a search box: part of
  /// the name, or part of the phone number however it is formatted.
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    if (name.toLowerCase().contains(q)) return true;
    final digits = _localDigits(q);
    return digits.isNotEmpty && _localDigits(phone).contains(digits);
  }

  /// Same phone number, however either was typed. How the front desk spots
  /// that a "new" walk-in is already on file.
  bool hasPhone(String other) {
    final mine = _localDigits(phone);
    return mine.length >= 7 && mine == _localDigits(other);
  }
}

/// Digits only, with a Philippine +63 prefix rewritten to the local 0, so
/// "+63 917 123 4567" and "0917-123-4567" compare equal.
String _localDigits(String s) {
  final d = s.replaceAll(RegExp(r'\D'), '');
  return d.startsWith('63') && d.length == 12 ? '0${d.substring(2)}' : d;
}

/// A remark on a chart in the patient list. The rules live in the database
/// (`public.search_patients`); these are only their names.
enum PatientFlag {
  recall('recall', 'For recall', Icons.event_repeat_outlined),
  balance('balance', 'With balance', Icons.account_balance_wallet_outlined),
  noContact('no_contact', 'No contact info', Icons.phone_disabled_outlined),
  attention('attention', 'Needs attention', Icons.priority_high_rounded),
  pedia('pedia', 'Pedia', Icons.child_care_outlined),
  adult('adult', 'Adult', Icons.person_outline);

  const PatientFlag(this.wire, this.label, this.icon);

  final String wire;
  final String label;
  final IconData icon;

  /// Age groups describe the patient; the rest ask someone to act.
  bool get isAgeGroup => this == pedia || this == adult;

  static PatientFlag? fromWire(String value) {
    for (final f in values) {
      if (f.wire == value) return f;
    }
    return null;
  }
}

/// What the patient list can be sorted by.
enum PatientSort {
  name('name'),
  age('age'),
  firstVisit('first_visit'),
  lastVisit('last_visit'),
  nextVisit('next_visit'),
  visits('visits'),
  balance('balance');

  const PatientSort(this.wire);

  final String wire;
}

/// Why a chart [PatientFlag.attention] needs attention.
enum AttentionReason {
  unbookedPlan('unbooked_plan', 'Planned treatment not booked'),
  noShow('no_show', 'Missed the last visit'),
  overdueBalance('overdue_balance', 'Bill unpaid 30+ days');

  const AttentionReason(this.wire, this.label);

  final String wire;
  final String label;

  static AttentionReason? fromWire(String value) {
    for (final r in values) {
      if (r.wire == value) return r;
    }
    return null;
  }
}

/// A chart in the patient list, with what the list shows of it. From
/// `public.search_patients`.
class PatientListing {
  const PatientListing({
    required this.patient,
    this.completedVisits = 0,
    this.firstVisitAt,
    this.lastVisitAt,
    this.nextVisitAt,
    this.lastVisitService,
    this.lastVisitDoctor,
    this.lastVisitMissed = false,
    this.balance = 0,
    this.plannedCount = 0,
    this.age,
    this.flags = const {},
    this.attention = const {},
  });

  final Patient patient;
  final int completedVisits;

  /// First and last COMPLETED visit.
  final DateTime? firstVisitAt;
  final DateTime? lastVisitAt;
  final DateTime? nextVisitAt;

  /// The most recent visit that is over, completed or missed.
  final String? lastVisitService;
  final String? lastVisitDoctor;
  final bool lastVisitMissed;

  /// Owed on issued bills.
  final double balance;

  /// Treatment plan items not done yet (dental clinics).
  final int plannedCount;
  final int? age;
  final Set<PatientFlag> flags;
  final Set<AttentionReason> attention;

  factory PatientListing.fromJson(Map<String, dynamic> json) => PatientListing(
        patient: Patient.fromJson(json),
        completedVisits: (json['completed_visits'] as num?)?.toInt() ?? 0,
        firstVisitAt: _time(json['first_visit_at']),
        lastVisitAt: _time(json['last_visit_at']),
        nextVisitAt: _time(json['next_visit_at']),
        lastVisitService: json['last_visit_service'] as String?,
        lastVisitDoctor: json['last_visit_doctor'] as String?,
        lastVisitMissed: json['last_visit_status'] == 'no_show',
        balance: (json['balance'] as num?)?.toDouble() ?? 0,
        plannedCount: (json['planned_count'] as num?)?.toInt() ?? 0,
        age: (json['age'] as num?)?.toInt(),
        flags: {
          for (final w in json['flags'] as List<dynamic>? ?? const [])
            if (PatientFlag.fromWire(w as String) case final f?) f,
        },
        attention: {
          for (final w in json['attention'] as List<dynamic>? ?? const [])
            if (AttentionReason.fromWire(w as String) case final r?) r,
        },
      );
}

/// One page of a patient search, how many match in all, and how many of the
/// whole search carry each remark (before the filters).
class PatientPage {
  const PatientPage({
    required this.patients,
    required this.total,
    this.counts = const {},
    this.all,
  });

  final List<PatientListing> patients;

  /// Matches after the filters.
  final int total;
  final Map<PatientFlag, int> counts;

  /// Matches before the filters. Null from a database without them.
  final int? all;

  factory PatientPage.fromJson(Map<String, dynamic> json) {
    final counts = json['counts'] as Map<String, dynamic>? ?? const {};
    return PatientPage(
      total: (json['total'] as num?)?.toInt() ?? 0,
      all: (counts['all'] as num?)?.toInt(),
      counts: {
        for (final f in PatientFlag.values)
          if (counts[f.wire] case final num n) f: n.toInt(),
      },
      patients: [
        for (final p in json['patients'] as List<dynamic>? ?? const [])
          PatientListing.fromJson(p as Map<String, dynamic>),
      ],
    );
  }
}

DateTime? _time(Object? value) =>
    value == null ? null : DateTime.parse(value as String).toLocal();
