import { format } from 'date-fns';

import type { Clinic } from '../models/clinic';
import { type Invoice, paymentMethodMeta } from '../models/invoice';
import { formatPeso } from '../models/money';
import type { Patient } from '../models/patient';

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
///
/// [logoSrc] turns the clinic's logo URL into one the page can load: a
/// bundled `asset:` logo becomes the address the build serves it at.
export function buildStatementHtml(args: {
  clinic: Clinic;
  patient: Patient;
  invoices: Invoice[];
  printedAt?: Date;
  logoSrc?: (url: string) => string | null;
}): string {
  const { clinic, patient } = args;
  const now = args.printedAt ?? new Date();
  // Oldest first, as a statement reads.
  const bills = args.invoices.filter((v) => v.status !== 'void').sort((a, b) => when(a).getTime() - when(b).getTime());

  const charged = bills.reduce((s, v) => s + v.total, 0);
  const paid = bills.reduce((s, v) => s + v.amountPaid, 0);
  const due = bills.reduce((s, v) => s + v.balance, 0);
  const allPaid = bills.length > 0 && due <= 0 && !bills.some((v) => v.isDraft);

  const logo = clinic.logoUrl == null || clinic.logoUrl.trim() === '' ? null : (args.logoSrc ?? ((u) => u))(clinic.logoUrl);
  const contact = [clinic.address?.trim(), clinic.contactPhone?.trim()].filter((s): s is string => !!s);
  const patientLines = [
    ...(patient.chartNumber?.trim() ? [`Chart no. ${patient.chartNumber.trim()}`] : []),
    ...(patient.phone.trim() ? [patient.phone.trim()] : []),
    ...(patient.address?.trim() ? [patient.address.trim()] : []),
  ];
  const title = allPaid ? 'Payment summary' : 'Statement of account';

  let out =
    '<!doctype html><html lang="en"><head><meta charset="utf-8">' +
    `<title>${e(fileTitle(patient, now))}</title>` +
    `<style>${css}</style></head><body>` +
    '<header class="top"><div class="clinic">' +
    (logo == null ? '' : `<img class="logo" src="${e(logo)}" alt="">`) +
    `<div><div class="clinic-name">${e(clinic.name)}</div>` +
    (contact.length === 0 ? '' : `<div class="muted">${contact.map(e).join(' · ')}</div>`) +
    '</div></div><div class="doc">' +
    `<div class="doc-title">${title}</div>` +
    `<div class="muted">Printed ${e(dateTime(now))}</div>` +
    '</div></header>' +
    '<section class="patient"><div class="label">Patient</div>' +
    `<div class="patient-name">${e(patient.name)}</div>` +
    (patientLines.length === 0 ? '' : `<div class="muted">${patientLines.map(e).join(' · ')}</div>`) +
    '</section>';

  for (const v of bills) out += bill(v);

  out +=
    '<section class="summary"><table>' +
    sumRow(`Total charges (${bills.length} ${bills.length === 1 ? 'bill' : 'bills'})`, charged) +
    sumRow('Total paid', paid) +
    `<tr class="due"><td>Balance due</td><td>${e(formatPeso(due > 0 ? due : 0))}</td></tr>` +
    '</table></section>' +
    '<footer>' +
    (bills.some((v) => v.isDraft)
      ? '<p>Bills marked <b>Estimate</b> are not final yet; their amounts may change before they are issued.</p>'
      : '') +
    '<p>This statement is not an official receipt.</p>' +
    '</footer></body></html>';
  return out;
}

/// "Statement - Juan Dela Cruz - 2026-09-30": the name the browser offers
/// when the page is saved as a PDF.
function fileTitle(patient: Patient, at: Date): string {
  return `Statement - ${patient.name} - ${format(at, 'yyyy-MM-dd')}`;
}

function when(v: Invoice): Date {
  return v.visitAt ?? v.issuedAt ?? v.createdAt;
}

function bill(v: Invoice): string {
  const visit = [date(when(v)), ...(v.visitService != null ? [v.visitService] : []), ...(v.visitDoctor != null ? [`Dr. ${v.visitDoctor}`] : [])];
  const [tag, tagClass] =
    v.status === 'draft' ? ['Estimate', 'draft'] : v.status === 'paid' ? ['Paid', 'paid'] : v.amountPaid > 0 ? ['Partly paid', 'open'] : ['Unpaid', 'open'];

  let out =
    '<section class="bill"><div class="bill-head"><div>' +
    `<div class="bill-title">${e(visit.join(' · '))}</div>` +
    `<div class="muted">${e(v.number ?? 'Not yet issued')}${v.issuedAt == null ? '' : ` · issued ${e(date(v.issuedAt))}`}</div>` +
    `</div><span class="tag ${tagClass}">${tag}</span></div>` +
    '<table class="lines"><thead><tr><th>Item</th>' +
    '<th class="n">Qty</th><th class="n">Price</th>' +
    '<th class="n">Amount</th></tr></thead><tbody>';
  if (v.items.length === 0) out += '<tr><td colspan="4" class="muted">No items</td></tr>';
  for (const i of v.items) {
    out +=
      `<tr><td>${e(i.description)}</td>` +
      `<td class="n">${i.quantity}</td>` +
      `<td class="n">${e(formatPeso(i.unitPrice))}</td>` +
      `<td class="n">${e(formatPeso(i.amount))}</td></tr>`;
  }
  out += '</tbody><tfoot>';
  if (v.discountAmount > 0) {
    out += footRow('Subtotal', formatPeso(v.subtotal));
    out += footRow(`Discount${v.discountReason == null ? '' : ` (${v.discountReason})`}`, `−${formatPeso(v.discountAmount)}`);
  }
  out += footRow('Total', formatPeso(v.total), true);
  for (const p of v.activePayments) {
    const ref = p.reference == null || p.reference.trim() === '' ? '' : ` · ref ${p.reference.trim()}`;
    out += footRow(`Paid ${date(p.receivedAt)} · ${paymentMethodMeta[p.method].label}${ref}`, `−${formatPeso(p.amount)}`);
  }
  if (v.activePayments.length > 0 || v.balance > 0) {
    out += footRow('Balance', formatPeso(v.balance > 0 ? v.balance : 0), true);
  }
  out += '</tfoot></table>';
  if (v.notes != null && v.notes.trim() !== '') out += `<p class="note">${e(v.notes.trim())}</p>`;
  out += '</section>';
  return out;
}

function footRow(label: string, amount: string, strong = false): string {
  return `<tr${strong ? ' class="strong"' : ''}><td colspan="3">${e(label)}</td><td class="n">${e(amount)}</td></tr>`;
}

function sumRow(label: string, amount: number): string {
  return `<tr><td>${e(label)}</td><td>${e(formatPeso(amount))}</td></tr>`;
}

function date(d: Date): string {
  return format(d, 'MMM d, y');
}

function dateTime(d: Date): string {
  return format(d, 'MMM d, y · h:mm a');
}

/// Safe in text and in double-quoted attributes; leaves URLs' slashes be.
function e(s: string): string {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}

const css = `
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
`;
