import 'package:intl/intl.dart';

import 'money.dart';

/// Which part of the clinic a change was to. Filters the activity log.
enum AuditArea {
  patients('Patients', [
    'patients',
    'persons',
    'patient_intakes',
    'chart_notes',
    'visit_notes',
    'dental_chart_entries',
  ]),
  visits('Visits', ['appointments']),
  billing('Billing', ['invoices', 'invoice_items', 'payments', 'expenses']),
  clinic('Clinic & staff', [
    'clinics',
    'services',
    'doctors',
    'doctor_time_off',
    'clinic_memberships',
    'staff_invites',
  ]);

  const AuditArea(this.label, this.tables);

  final String label;

  /// The `audit_log.table_name`s in this area.
  final List<String> tables;
}

enum AuditAction {
  insert,
  update,
  delete;

  static AuditAction fromWire(String value) => AuditAction.values.byName(value);
}

/// One field of a record, before and after, ready to show.
class AuditChange {
  const AuditChange(this.label, this.before, this.after);

  final String label;

  /// Null when there was no before (an insert) or no after (a delete).
  final String? before;
  final String? after;
}

/// One change to one record, from `public.audit_entries` — see
/// 20261005120100_audit_log in health-platform-be. Readable by the clinic's
/// admins only.
class AuditEntry {
  const AuditEntry({
    required this.id,
    required this.table,
    required this.rowId,
    required this.action,
    required this.oldValues,
    required this.newValues,
    required this.createdAt,
    required this.txId,
    this.patientId,
    this.patientName,
    this.actorId,
    this.actorName,
    this.actorRole,
  });

  final int id;
  final String table;
  final String rowId;
  final AuditAction action;
  final Map<String, dynamic> oldValues;
  final Map<String, dynamic> newValues;
  final DateTime createdAt;

  /// Shared by every change made in the same go.
  final int txId;
  final String? patientId;
  final String? patientName;

  /// Null for a change nobody signed in made: a scheduled job, or the
  /// platform operator.
  final String? actorId;
  final String? actorName;

  /// `admin`, `doctor`, `assistant`, `patient`, or null.
  final String? actorRole;

  factory AuditEntry.fromJson(Map<String, dynamic> json) => AuditEntry(
        id: (json['id'] as num).toInt(),
        table: json['table_name'] as String,
        rowId: json['row_id'] as String,
        action: AuditAction.fromWire(json['action'] as String),
        oldValues: (json['old_values'] as Map?)?.cast<String, dynamic>() ?? const {},
        newValues: (json['new_values'] as Map?)?.cast<String, dynamic>() ?? const {},
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
        txId: (json['tx_id'] as num).toInt(),
        patientId: json['patient_id'] as String?,
        patientName: json['patient_name'] as String?,
        actorId: json['actor_id'] as String?,
        actorName: json['actor_name'] as String?,
        actorRole: json['actor_role'] as String?,
      );

  /// "Maria Santos", or "System" for a change nobody signed in made.
  String get actorLabel =>
      actorName ?? (actorId == null ? 'System' : 'Former user');

  /// "Doctor", "Front desk", "Admin", "Patient", or null.
  String? get actorRoleLabel => switch (actorRole) {
        'admin' => 'Admin',
        'doctor' => 'Doctor',
        'assistant' => 'Front desk',
        'patient' => 'Patient',
        _ => null,
      };

  /// What kind of record: "Visit", "Payment", "Medical note".
  String get recordLabel => _recordLabels[table] ?? _humanize(table);

  AuditArea? get area {
    for (final a in AuditArea.values) {
      if (a.tables.contains(table)) return a;
    }
    return null;
  }

  /// "added", "changed", "removed" — or the word that fits the record better.
  String get verb => switch ((table, action)) {
        ('patients', AuditAction.insert) => 'registered',
        ('payments', AuditAction.insert) => 'recorded',
        ('invoices', AuditAction.insert) => 'drafted',
        ('appointments', AuditAction.insert) => 'booked',
        (_, AuditAction.insert) => 'added',
        (_, AuditAction.update) => 'changed',
        (_, AuditAction.delete) => 'removed',
      };

  /// "Visit booked", "Payment voided"… a short headline for the entry.
  String get headline {
    if (action == AuditAction.update) {
      final status = newValues['status'];
      if (status is String) {
        return '$recordLabel ${_humanize(status).toLowerCase()}';
      }
      if (newValues['voided_at'] != null) return '$recordLabel voided';
    }
    return '$recordLabel $verb';
  }

  /// The fields worth showing, in a stable order.
  ///
  /// An update lists what changed. An insert or delete lists the record as it
  /// was, leaving out the ids and stamps nobody reads. A reference to another
  /// record (a doctor, a service) is shown as "changed", not as its id.
  List<AuditChange> get changes {
    final isUpdate = action == AuditAction.update;
    final source = action == AuditAction.delete ? oldValues : newValues;
    final out = <AuditChange>[];

    // A chart's insert or delete carries who the patient is.
    final person = source['person'];
    if (person is Map) {
      for (final e in person.cast<String, dynamic>().entries) {
        final v = formatAuditValue(e.key, e.value);
        if (v == null) continue;
        out.add(action == AuditAction.delete
            ? AuditChange(fieldLabel(e.key), v, null)
            : AuditChange(fieldLabel(e.key), null, v));
      }
    }

    for (final key in source.keys) {
      if (key == 'person' || _hidden.contains(key)) continue;
      final isRef = key.endsWith('_id') || key.endsWith('_by');
      if (isUpdate) {
        out.add(isRef
            ? AuditChange(fieldLabel(key), null, 'changed')
            : AuditChange(fieldLabel(key), formatAuditValue(key, oldValues[key]) ?? '—',
                formatAuditValue(key, newValues[key]) ?? '—'));
      } else {
        if (isRef) continue;
        final v = formatAuditValue(key, source[key]);
        if (v == null) continue;
        out.add(action == AuditAction.delete
            ? AuditChange(fieldLabel(key), v, null)
            : AuditChange(fieldLabel(key), null, v));
      }
    }
    return out;
  }

  static const _hidden = {'id', 'clinic_id', 'tx_id', 'imported'};

  static const _recordLabels = {
    'patients': 'Patient',
    'persons': 'Contact details',
    'patient_intakes': 'Patient form',
    'chart_notes': 'Medical note',
    'visit_notes': 'Visit note',
    'dental_chart_entries': 'Tooth chart',
    'appointments': 'Visit',
    'invoices': 'Bill',
    'invoice_items': 'Bill item',
    'payments': 'Payment',
    'expenses': 'Expense',
    'clinics': 'Clinic details',
    'services': 'Service',
    'doctors': 'Doctor',
    'doctor_time_off': 'Time off',
    'clinic_memberships': 'Staff member',
    'staff_invites': 'Staff code',
  };
}

const _fieldLabels = {
  'full_name': 'Name',
  'date_of_birth': 'Date of birth',
  'scheduled_at': 'Time',
  'ends_at': 'Ends',
  'duration_minutes': 'Minutes',
  'doctor_id': 'Doctor',
  'service_id': 'Service',
  'service_name': 'Service',
  'patient_id': 'Patient',
  'appointment_id': 'Visit',
  'invoice_id': 'Bill',
  'body': 'Note',
  'patient_note': 'Note to the patient',
  'chart_number': 'Chart no.',
  'emergency_contact_name': 'Emergency contact',
  'emergency_contact_phone': 'Emergency contact phone',
  'amount_paid': 'Paid',
  'discount_amount': 'Discount',
  'unit_price': 'Unit price',
  'is_active': 'Active',
  'available_weekdays': 'Working days',
  'available_time_slots': 'Hours',
  'starts_on': 'From',
  'ends_on': 'To',
  'spent_on': 'Date',
  'received_at': 'Received',
  'code': 'Treatment',
  'tooth': 'Tooth',
  'role': 'Role',
  'branch_locked': 'Branch admin',
  'recall_months': 'Recall (months)',
  'seed_color': 'Colour',
  'signed_name': 'Signed by',
  'consent_at': 'Consent given',
};

/// "date_of_birth" → "Date of birth", with the few that read better by hand.
String fieldLabel(String key) {
  final known = _fieldLabels[key];
  if (known != null) return known;
  var k = key;
  if (k.endsWith('_id')) k = k.substring(0, k.length - 3);
  if (k.endsWith('_by')) k = '${k.substring(0, k.length - 3)} by';
  return _humanize(k);
}

const _moneyFields = {
  'amount',
  'price',
  'total',
  'subtotal',
  'balance',
  'amount_paid',
  'unit_price',
  'discount_amount',
};

final _isoDateTime = RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}');
final _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// A stored value as a person would write it. Null for nothing to show.
String? formatAuditValue(String key, Object? value) {
  if (value == null) return null;
  if (value is bool) return value ? 'Yes' : 'No';
  if (value is num) {
    return _moneyFields.contains(key) ? formatPeso(value) : '$value';
  }
  if (value is List) {
    if (value.isEmpty) return null;
    return value.map((v) => v is String ? _humanize(v) : '$v').join(', ');
  }
  if (value is Map) return null;
  final s = value.toString();
  if (s.trim().isEmpty) return null;
  if (_isoDateTime.hasMatch(s)) {
    final t = DateTime.tryParse(s);
    if (t != null) return DateFormat('d MMM y, h:mm a').format(t.toLocal());
  }
  if (_isoDate.hasMatch(s)) {
    final d = DateTime.tryParse(s);
    if (d != null) return DateFormat('d MMM y').format(d);
  }
  // An enum value (in_consultation, gcash) rather than something typed.
  if (RegExp(r'^[a-z]+(_[a-z]+)*$').hasMatch(s) && !_freeText.contains(key)) {
    return _humanize(s);
  }
  return s;
}

/// Fields people type into, never tidied up.
const _freeText = {
  'full_name',
  'body',
  'patient_note',
  'note',
  'notes',
  'description',
  'reason',
  'address',
  'occupation',
  'email',
  'signed_name',
  'medications',
  'treatment_details',
  'name',
  'label',
};

String _humanize(String snake) {
  final words = snake.replaceAll('_', ' ').trim();
  if (words.isEmpty) return words;
  return words[0].toUpperCase() + words.substring(1);
}

/// One page of the log, newest first.
class AuditPage {
  const AuditPage(this.entries, {required this.hasMore});

  final List<AuditEntry> entries;
  final bool hasMore;
}
