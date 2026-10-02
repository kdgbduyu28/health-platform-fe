import 'dart:convert';

import 'package:intl/intl.dart';

import '../models/clinic.dart';
import '../models/invoice.dart';
import '../models/money.dart';
import '../models/patient.dart';
import '../theme/brand.dart';

/// A printable statement of one patient's bills: every line charged, every
/// discount, every payment, and what is left to pay. The patient takes it
/// home, or files it with an HMO or an employer.
///
/// A self-contained HTML page (no scripts, no outside styles) sized for A4
/// or Letter. `printHtml` hands it to the browser's print dialog, which
/// prints it or saves it as a PDF.
///
/// It is not an official receipt: in the Philippines only a BIR-registered
/// receipt is one, so the page says so at the foot.
///
/// Voided bills are left out. A draft is printed as an estimate, because its
/// lines and discount may still change.
String buildStatementHtml({
  required Clinic clinic,
  required Patient patient,
  required List<Invoice> invoices,
  DateTime? printedAt,
}) {
  final now = printedAt ?? DateTime.now();
  // Oldest first, as a statement reads.
  final bills = [
    for (final v in invoices)
      if (v.status != InvoiceStatus.voided) v,
  ]..sort((a, b) => _when(a).compareTo(_when(b)));

  final charged = bills.fold<double>(0, (s, v) => s + v.total);
  final paid = bills.fold<double>(0, (s, v) => s + v.amountPaid);
  final due = bills.fold<double>(0, (s, v) => s + v.balance);
  final allPaid = bills.isNotEmpty && due <= 0 && !bills.any((v) => v.isDraft);

  final logo = _logoSrc(clinic.logoUrl);
  final contact = [
    if (clinic.address case final a? when a.trim().isNotEmpty) a.trim(),
    if (clinic.contactPhone case final p? when p.trim().isNotEmpty) p.trim(),
  ];
  final patientLines = [
    if (patient.chartNumber case final n? when n.trim().isNotEmpty)
      'Chart no. ${n.trim()}',
    if (patient.phone.trim().isNotEmpty) patient.phone.trim(),
    if (patient.address case final a? when a.trim().isNotEmpty) a.trim(),
  ];
  final title = allPaid ? 'Payment summary' : 'Statement of account';

  final out = StringBuffer()
    ..write('<!doctype html><html lang="en"><head><meta charset="utf-8">')
    ..write('<title>${_e(_fileTitle(patient, now))}</title>')
    ..write('<style>$_css</style></head><body>')
    ..write('<header class="top"><div class="clinic">')
    ..write(logo == null ? '' : '<img class="logo" src="${_e(logo)}" alt="">')
    ..write('<div><div class="clinic-name">${_e(clinic.name)}</div>')
    ..write(contact.isEmpty
        ? ''
        : '<div class="muted">${contact.map(_e).join(' · ')}</div>')
    ..write('</div></div><div class="doc">')
    ..write('<div class="doc-title">$title</div>')
    ..write('<div class="muted">Printed ${_e(_dateTime(now))}</div>')
    ..write('</div></header>')
    ..write('<section class="patient"><div class="label">Patient</div>')
    ..write('<div class="patient-name">${_e(patient.name)}</div>')
    ..write(patientLines.isEmpty
        ? ''
        : '<div class="muted">${patientLines.map(_e).join(' · ')}</div>')
    ..write('</section>');

  for (final v in bills) {
    out.write(_bill(v));
  }

  out
    ..write('<section class="summary"><table>')
    ..write(_sumRow(
        'Total charges (${bills.length} '
        '${bills.length == 1 ? 'bill' : 'bills'})',
        charged))
    ..write(_sumRow('Total paid', paid))
    ..write('<tr class="due"><td>Balance due</td>'
        '<td>${_e(formatPeso(due > 0 ? due : 0))}</td></tr>')
    ..write('</table></section>')
    ..write('<footer>')
    ..write(bills.any((v) => v.isDraft)
        ? '<p>Bills marked <b>Estimate</b> are not final yet; their amounts '
            'may change before they are issued.</p>'
        : '')
    ..write('<p>This statement is not an official receipt.</p>')
    ..write('</footer></body></html>');
  return out.toString();
}

/// "Statement - Juan Dela Cruz - 2026-09-30": the name the browser offers
/// when the page is saved as a PDF.
String _fileTitle(Patient patient, DateTime at) =>
    'Statement - ${patient.name} - ${DateFormat('yyyy-MM-dd').format(at)}';

DateTime _when(Invoice v) => v.visitAt ?? v.issuedAt ?? v.createdAt;

String _bill(Invoice v) {
  final visit = [
    _date(_when(v)),
    if (v.visitService case final s?) s,
    if (v.visitDoctor case final d?) 'Dr. $d',
  ];
  final (tag, tagClass) = switch (v.status) {
    InvoiceStatus.draft => ('Estimate', 'draft'),
    InvoiceStatus.paid => ('Paid', 'paid'),
    _ when v.amountPaid > 0 => ('Partly paid', 'open'),
    _ => ('Unpaid', 'open'),
  };

  final out = StringBuffer()
    ..write('<section class="bill"><div class="bill-head"><div>')
    ..write('<div class="bill-title">${_e(visit.join(' · '))}</div>')
    ..write('<div class="muted">${_e(v.number ?? 'Not yet issued')}'
        '${v.issuedAt == null ? '' : ' · issued ${_e(_date(v.issuedAt!))}'}'
        '</div>')
    ..write('</div><span class="tag $tagClass">$tag</span></div>')
    ..write('<table class="lines"><thead><tr><th>Item</th>'
        '<th class="n">Qty</th><th class="n">Price</th>'
        '<th class="n">Amount</th></tr></thead><tbody>');
  if (v.items.isEmpty) {
    out.write('<tr><td colspan="4" class="muted">No items</td></tr>');
  }
  for (final i in v.items) {
    out.write('<tr><td>${_e(i.description)}</td>'
        '<td class="n">${i.quantity}</td>'
        '<td class="n">${_e(formatPeso(i.unitPrice))}</td>'
        '<td class="n">${_e(formatPeso(i.amount))}</td></tr>');
  }
  out.write('</tbody><tfoot>');
  if (v.discountAmount > 0) {
    out
      ..write(_footRow('Subtotal', formatPeso(v.subtotal)))
      ..write(_footRow(
          'Discount${v.discountReason == null ? '' : ' (${v.discountReason})'}',
          '−${formatPeso(v.discountAmount)}'));
  }
  out.write(_footRow('Total', formatPeso(v.total), strong: true));
  for (final p in v.activePayments) {
    out.write(_footRow(
        'Paid ${_date(p.receivedAt)} · ${p.method.displayName}'
        '${p.reference == null || p.reference!.trim().isEmpty ? '' : ' · ref ${p.reference!.trim()}'}',
        '−${formatPeso(p.amount)}'));
  }
  if (v.activePayments.isNotEmpty || v.balance > 0) {
    out.write(_footRow('Balance', formatPeso(v.balance > 0 ? v.balance : 0),
        strong: true));
  }
  out.write('</tfoot></table>');
  if (v.notes case final n? when n.trim().isNotEmpty) {
    out.write('<p class="note">${_e(n.trim())}</p>');
  }
  out.write('</section>');
  return out.toString();
}

String _footRow(String label, String amount, {bool strong = false}) =>
    '<tr${strong ? ' class="strong"' : ''}><td colspan="3">${_e(label)}</td>'
    '<td class="n">${_e(amount)}</td></tr>';

String _sumRow(String label, double amount) =>
    '<tr><td>${_e(label)}</td><td>${_e(formatPeso(amount))}</td></tr>';

/// Where the page loads the clinic's logo from. Artwork bundled in the
/// package sits in the web build's asset folder; the print page resolves it
/// against the app's base URL.
String? _logoSrc(String? url) {
  if (url == null || url.trim().isEmpty) return null;
  if (url.startsWith(Brand.bundledAssetScheme)) {
    return 'assets/packages/${Brand.package}/'
        '${url.substring(Brand.bundledAssetScheme.length)}';
  }
  return url;
}

String _date(DateTime d) => DateFormat('MMM d, y').format(d);
String _dateTime(DateTime d) => DateFormat('MMM d, y · h:mm a').format(d);
// Safe in text and in double-quoted attributes; leaves URLs' slashes be.
String _e(String s) => const HtmlEscape(HtmlEscapeMode.attribute).convert(s);

const _css = '''
@page { size: auto; margin: 14mm; }
* { box-sizing: border-box; }
body { margin: 0; font: 11pt/1.4 -apple-system, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; color: #1a1a1a; background: #fff; }
.muted { color: #666; font-size: 9.5pt; }
.top { display: flex; justify-content: space-between; align-items: flex-start; gap: 16px; padding-bottom: 12px; border-bottom: 2px solid #1a1a1a; }
.clinic { display: flex; gap: 12px; align-items: center; }
.logo { width: 48px; height: 48px; object-fit: contain; }
.clinic-name { font-size: 15pt; font-weight: 700; }
.doc { text-align: right; }
.doc-title { font-size: 13pt; font-weight: 700; text-transform: uppercase; letter-spacing: .04em; }
.patient { margin: 14px 0 6px; }
.label { font-size: 8.5pt; text-transform: uppercase; letter-spacing: .06em; color: #666; }
.patient-name { font-size: 12.5pt; font-weight: 700; }
.bill { margin-top: 14px; break-inside: avoid; page-break-inside: avoid; }
.bill-head { display: flex; justify-content: space-between; align-items: flex-start; gap: 12px; margin-bottom: 4px; }
.bill-title { font-weight: 700; }
.tag { font-size: 8.5pt; font-weight: 700; text-transform: uppercase; letter-spacing: .05em; padding: 2px 8px; border: 1px solid; border-radius: 10px; white-space: nowrap; }
.tag.paid { color: #2e7d32; }
.tag.open { color: #b34700; }
.tag.draft { color: #666; }
table { width: 100%; border-collapse: collapse; }
.lines th { text-align: left; font-size: 9pt; color: #666; font-weight: 600; border-bottom: 1px solid #ccc; padding: 4px 6px; }
.lines td { padding: 4px 6px; border-bottom: 1px solid #eee; vertical-align: top; }
.lines tfoot td { border-bottom: none; padding: 3px 6px; }
.lines tfoot td:first-child { text-align: right; color: #444; }
.lines tfoot tr.strong td { font-weight: 700; color: #1a1a1a; border-top: 1px solid #ccc; }
.n { text-align: right; white-space: nowrap; font-variant-numeric: tabular-nums; }
th.n { text-align: right; }
.note { margin: 4px 6px 0; font-size: 9.5pt; color: #444; }
.summary { margin-top: 18px; display: flex; justify-content: flex-end; break-inside: avoid; page-break-inside: avoid; }
.summary table { width: auto; min-width: 45%; }
.summary td { padding: 4px 6px; }
.summary td:last-child { text-align: right; font-variant-numeric: tabular-nums; }
.summary tr.due td { font-weight: 700; font-size: 12pt; border-top: 2px solid #1a1a1a; }
footer { margin-top: 24px; font-size: 9pt; color: #666; }
footer p { margin: 2px 0; }
''';
