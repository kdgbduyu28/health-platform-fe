import { format } from 'date-fns';

import type { Clinic } from '../models/clinic';
import type { Patient } from '../models/patient';
import { type Prescription, rxItemTitle } from '../models/prescription';

/// A printable prescription on the clinic's letterhead: the patient, the
/// date, each medicine with its count and instructions, and the doctor's
/// name with their PRC, PTR and S2 numbers over a line for the signature.
///
/// A self-contained HTML page sized for A5 (or whatever the printer has),
/// like the billing statement; `printHtml` opens the print dialog on it. A
/// voided one prints with VOID across it, so a copy never passes as live.
export function buildPrescriptionHtml(args: {
  clinic: Clinic;
  patient: Patient;
  rx: Prescription;
  logoSrc?: (url: string) => string | null;
}): string {
  const { clinic, patient, rx } = args;
  const logo = clinic.logoUrl == null || clinic.logoUrl.trim() === '' ? null : (args.logoSrc ?? ((u) => u))(clinic.logoUrl);
  const contact = [clinic.address?.trim(), clinic.contactPhone?.trim()].filter((s): s is string => !!s);
  const patientBits = [
    ...(patient.age != null ? [`Age ${patient.age}`] : []),
    ...(patient.address?.trim() ? [patient.address.trim()] : []),
  ];
  const licences = [
    ...(rx.prcLicenseNo?.trim() ? [`PRC Lic. No. ${rx.prcLicenseNo.trim()}`] : []),
    ...(rx.ptrNo?.trim() ? [`PTR No. ${rx.ptrNo.trim()}`] : []),
    ...(rx.s2LicenseNo?.trim() ? [`S2 No. ${rx.s2LicenseNo.trim()}`] : []),
  ];

  let out =
    '<!doctype html><html lang="en"><head><meta charset="utf-8">' +
    `<title>${e(`Prescription - ${patient.name} - ${format(rx.issuedAt, 'yyyy-MM-dd')}`)}</title>` +
    `<style>${css}</style></head><body>` +
    (rx.isVoid ? '<div class="void">VOID</div>' : '') +
    '<header class="top">' +
    (logo == null ? '' : `<img class="logo" src="${e(logo)}" alt="">`) +
    `<div><div class="clinic-name">${e(clinic.name)}</div>` +
    (contact.length === 0 ? '' : `<div class="muted">${contact.map(e).join(' · ')}</div>`) +
    '</div></header>' +
    '<section class="patient"><div class="row">' +
    `<div><span class="label">Patient</span> <b>${e(patient.name)}</b></div>` +
    `<div><span class="label">Date</span> ${e(format(rx.issuedAt, 'MMM d, y'))}</div></div>` +
    (patientBits.length === 0 ? '' : `<div class="muted">${patientBits.map(e).join(' · ')}</div>`) +
    '</section>' +
    '<div class="rx">&#8478;</div><ol class="items">';
  for (const i of rx.items) {
    out +=
      `<li><div class="drug"><span>${e(rxItemTitle(i))}</span>` +
      (i.quantity != null ? `<span class="qty">#${i.quantity}</span>` : '') +
      `</div><div class="sig">Sig: ${e(i.sig)}</div></li>`;
  }
  out += '</ol>';
  if (rx.notes != null && rx.notes.trim() !== '') out += `<p class="notes">${e(rx.notes.trim())}</p>`;
  out +=
    '<footer><div class="sign">' +
    `<div class="line"></div><div class="doctor">${e(rx.doctorName)}, MD</div>` +
    licences.map((l) => `<div class="muted">${e(l)}</div>`).join('') +
    '</div></footer></body></html>';
  return out;
}

function e(s: string): string {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}

const css = `
@page { size: A5; margin: 12mm; }
* { box-sizing: border-box; }
body { margin: 0; font: 11pt/1.45 -apple-system, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; color: #1a1a1a; background: #fff; position: relative; }
.muted { color: #666; font-size: 9.5pt; }
.top { display: flex; gap: 12px; align-items: center; padding-bottom: 10px; border-bottom: 2px solid #1a1a1a; }
.logo { width: 44px; height: 44px; object-fit: contain; }
.clinic-name { font-size: 14pt; font-weight: 700; }
.patient { margin: 12px 0 4px; }
.patient .row { display: flex; justify-content: space-between; gap: 12px; }
.label { font-size: 8.5pt; text-transform: uppercase; letter-spacing: .06em; color: #666; margin-right: 4px; }
.rx { font-size: 28pt; font-family: Georgia, "Times New Roman", serif; margin: 8px 0 0; }
.items { margin: 0 0 0 18px; padding: 0; }
.items li { margin: 0 0 10px; break-inside: avoid; page-break-inside: avoid; }
.drug { display: flex; justify-content: space-between; gap: 12px; font-weight: 700; }
.qty { white-space: nowrap; font-variant-numeric: tabular-nums; }
.sig { margin-top: 2px; }
.notes { margin: 12px 0 0; padding-top: 8px; border-top: 1px solid #ddd; }
footer { margin-top: 36px; display: flex; justify-content: flex-end; }
.sign { min-width: 55%; text-align: center; }
.line { border-top: 1px solid #1a1a1a; margin-bottom: 4px; }
.doctor { font-weight: 700; }
.void { position: fixed; top: 40%; left: 0; right: 0; text-align: center; font-size: 72pt; font-weight: 800; color: rgba(198, 40, 40, .25); transform: rotate(-24deg); pointer-events: none; }
`;
