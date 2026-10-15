import { buildStatementHtml } from '../src/billing/statement';
import { Clinic } from '../src/models/clinic';
import {
  type DentalCode,
  DentalChart,
  DentalEntry,
  type DentalEntryStatus,
  type Dentition,
  type ToothSurface,
  allowedStatuses,
  dentalEntryStatuses,
  dentitionForAge,
  describeTooth,
  lowerTeeth,
  surfaceLabelFor,
  toothName,
  universalLabel,
  upperTeeth,
} from '../src/models/dental_chart';
import { Invoice } from '../src/models/invoice';
import { Patient } from '../src/models/patient';

let seq = 0;

/// An entry recorded [minutes] after the first, so order is explicit.
function entry(
  tooth: number,
  code: DentalCode,
  opts: { status?: DentalEntryStatus; surfaces?: ToothSurface[]; visit?: string; minutes?: number } = {},
): DentalEntry {
  const { status = 'existing', surfaces = [], visit = null, minutes = 0 } = opts;
  return new DentalEntry(`e${seq++}`, tooth, code, status, new Set(surfaces), visit, null, new Date(2026, 0, 1, 0, minutes));
}

describe('tooth numbering', () => {
  test('FDI to Universal, permanent teeth', () => {
    const pairs: [number, string][] = [
      [18, '1'],
      [11, '8'],
      [21, '9'],
      [28, '16'],
      [38, '17'],
      [31, '24'],
      [41, '25'],
      [48, '32'],
    ];
    for (const [fdi, u] of pairs) expect(universalLabel(fdi)).toBe(u);
  });

  test('FDI to Universal, primary teeth', () => {
    const pairs: [number, string][] = [
      [55, 'A'],
      [51, 'E'],
      [61, 'F'],
      [65, 'J'],
      [75, 'K'],
      [71, 'O'],
      [81, 'P'],
      [85, 'T'],
    ];
    for (const [fdi, u] of pairs) expect(universalLabel(fdi)).toBe(u);
  });

  test('every tooth on the chart has a distinct Universal label', () => {
    for (const d of ['permanent', 'primary'] as Dentition[]) {
      const teeth = [...upperTeeth(d), ...lowerTeeth(d)];
      expect(new Set(teeth.map(universalLabel)).size).toBe(teeth.length);
    }
  });

  test('teeth are named the way a dentist says them', () => {
    expect(toothName(46)).toBe('Lower right first molar');
    expect(toothName(21)).toBe('Upper left central incisor');
    expect(toothName(38)).toBe('Lower left third molar');
    expect(toothName(55)).toBe('Upper right baby second molar');
  });

  test('front teeth have incisal and facial surfaces; upper ones palatal', () => {
    expect(surfaceLabelFor('O', 11)).toBe('Incisal');
    expect(surfaceLabelFor('B', 43)).toBe('Facial');
    expect(surfaceLabelFor('O', 36)).toBe('Occlusal');
    expect(surfaceLabelFor('L', 16)).toBe('Palatal');
    expect(surfaceLabelFor('L', 46)).toBe('Lingual');
  });

  test('children are charted on baby teeth by default', () => {
    expect(dentitionForAge(6)).toBe('primary');
    expect(dentitionForAge(30)).toBe('permanent');
    expect(dentitionForAge(null)).toBe('permanent');
  });
});

describe('the chart', () => {
  test('a filling replaces the decay on the surfaces it repairs', () => {
    const chart = new DentalChart([entry(46, 'caries', { surfaces: ['O', 'D'] }), entry(46, 'filling', { status: 'done', surfaces: ['O'], visit: 'v2', minutes: 5 })]);
    const t = chart.stateOf(46);
    expect(t.surfaces.get('O')).toBe('filling');
    expect(t.surfaces.get('D')).toBe('caries');
    expect(t.hasProblem).toBe(true);
  });

  test('order is by when it was recorded, not the order rows arrive', () => {
    const chart = new DentalChart([entry(46, 'filling', { status: 'done', surfaces: ['O'], minutes: 5 }), entry(46, 'caries', { surfaces: ['O'] })]);
    expect(chart.stateOf(46).surfaces.get('O')).toBe('filling');
  });

  test('planned work changes nothing until it is done', () => {
    const chart = new DentalChart([entry(46, 'caries', { surfaces: ['O'] }), entry(46, 'root_canal', { status: 'planned' })]);
    const t = chart.stateOf(46);
    expect(t.whole.size).toBe(0);
    expect(t.planned.map((e) => e.code)).toEqual(['root_canal']);
    expect(chart.plan.map((e) => e.tooth)).toEqual([46]);
  });

  test('an extraction clears the tooth; a later implant brings it back', () => {
    const extracted = new DentalChart([entry(36, 'filling', { surfaces: ['M', 'O'] }), entry(36, 'extraction', { status: 'done', visit: 'v1', minutes: 1 })]);
    expect(extracted.stateOf(36).missing).toBe(true);
    expect(extracted.stateOf(36).surfaces.size).toBe(0);
    expect(extracted.stateOf(36).headline).toBe('missing');

    const implanted = new DentalChart([...extracted.entries, entry(36, 'implant', { status: 'done', visit: 'v2', minutes: 2 })]);
    expect(implanted.stateOf(36).missing).toBe(false);
    expect(implanted.stateOf(36).headline).toBe('implant');
  });

  test('a crown covers every surface', () => {
    const chart = new DentalChart([entry(16, 'caries', { surfaces: ['O', 'D'] }), entry(16, 'crown', { status: 'done', visit: 'v1', minutes: 1 })]);
    const t = chart.stateOf(16);
    expect(t.surfaces.size).toBe(0);
    expect(t.headline).toBe('crown');
    expect(t.hasProblem).toBe(false);
  });

  test('a root canal is what the tooth shows even under a filling', () => {
    const chart = new DentalChart([entry(46, 'root_canal', { status: 'done', visit: 'v1' }), entry(46, 'filling', { status: 'done', surfaces: ['O'], visit: 'v1', minutes: 1 })]);
    expect(chart.stateOf(46).headline).toBe('root_canal');
    expect(chart.stateOf(46).surfaces.get('O')).toBe('filling');
  });

  test('lists what was recorded at one visit, in tooth order', () => {
    const chart = new DentalChart([
      entry(46, 'caries', { surfaces: ['O'], visit: 'v1' }),
      entry(16, 'sealant', { status: 'done', surfaces: ['O'], visit: 'v1' }),
      entry(21, 'crown', { status: 'planned' }),
    ]);
    expect(chart.atVisit('v1').map((e) => e.tooth)).toEqual([16, 46]);
    expect(chart.atVisit('v2')).toEqual([]);
  });

  test('knows which dentition has been charted', () => {
    expect(new DentalChart([entry(85, 'sealant')]).hasPrimaryTeeth).toBe(true);
    expect(new DentalChart([entry(85, 'sealant')]).hasPermanentTeeth).toBe(false);
  });

  test('an untouched tooth is empty and healthy', () => {
    const t = new DentalChart([]).stateOf(11);
    expect(t.isEmpty).toBe(true);
    expect(describeTooth(t)).toBe('Nothing recorded');
  });

  test('a tooth is described for a screen reader', () => {
    const chart = new DentalChart([entry(46, 'caries', { surfaces: ['O', 'D'] }), entry(46, 'crown', { status: 'planned' })]);
    expect(describeTooth(chart.stateOf(46))).toBe('decay on OD; 1 planned');
  });
});

describe('entries', () => {
  test('read from the table, surfaces in any order', () => {
    const e = DentalEntry.fromJson({
      id: 'x',
      tooth: 46,
      code: 'filling',
      status: 'done',
      surfaces: ['O', 'D', 'M'],
      appointment_id: 'a1',
      note: 'Composite',
      created_at: '2026-09-01T02:00:00Z',
    });
    expect(e.code).toBe('filling');
    expect(e.status).toBe('done');
    expect(e.describe('fdi')).toBe('Filling 46 · MOD');
    expect(e.describe('universal')).toBe('Filling 30 · MOD');
    expect(e.note).toBe('Composite');
  });

  test('read from the patient function, which has no note', () => {
    const e = DentalEntry.fromJson({ id: 'x', tooth: 46, code: 'root_canal', status: 'planned', surfaces: [], appointment_id: null });
    expect(e.note).toBeNull();
    expect(e.describe('fdi', { forPatient: true })).toBe('Root canal treatment 46');
  });

  test('a condition can only be found; an extraction never "found"', () => {
    expect(allowedStatuses('caries')).toEqual(['existing']);
    expect(allowedStatuses('extraction')).not.toContain('existing');
    expect(allowedStatuses('crown')).toEqual(dentalEntryStatuses);
  });
});

test('a dental vertical charts teeth; others do not', () => {
  const of = (kind: string | null) =>
    Clinic.fromJson({ id: 'c', name: 'C', slug: 'c', type: 'dental', clinic_type: { display_name: 'Dental', icon_name: 'medical_services', chart_kind: kind } });
  expect(of('dental').isDental).toBe(true);
  expect(of(null).isDental).toBe(false);
});

// ── Statements ──────────────────────────────────────────────────────────────

const clinic = Clinic.fromJson({
  id: 'c1',
  name: 'D-Touch Dental Clinic',
  slug: 'dtouchdental',
  type: 'dental',
  clinic_type: { display_name: 'Dental' },
  address: 'Quezon City',
  contact_phone: '0917 000 0000',
  logo_url: 'asset:assets/brand/dtouch_mark.png',
});

const patient = new Patient('chart-1', 'person-1', 'c1', 'Ana <Cruz>', '0917 555 0101', '', null, null, null, null, null, null, null, 'A-12');

const bill = (over: Record<string, unknown> = {}) =>
  Invoice.fromJson({
    id: 'inv-1',
    clinic_id: 'c1',
    patient_id: 'chart-1',
    status: 'issued',
    number: 'INV-000001',
    subtotal: 2500,
    discount_amount: 0,
    total: 2500,
    amount_paid: 0,
    created_at: '2026-09-20T02:00:00Z',
    issued_at: '2026-09-20T03:00:00Z',
    items: [
      { id: 'i1', description: 'Oral prophylaxis', quantity: 1, unit_price: 1500 },
      { id: 'i2', description: 'Fluoride', quantity: 2, unit_price: 500 },
    ],
    payments: [],
    appointment: { service_name: 'Cleaning', scheduled_at: '2026-09-20T01:00:00Z', doctor: { full_name: 'Maria Santos' } },
    ...over,
  });

describe('statements', () => {
  test("the bill query reads the visit's doctor", () => {
    expect(bill().visitDoctor).toBe('Maria Santos');
  });

  test('a statement lists every line, discount, payment and balance', () => {
    const paid = bill({
      id: 'inv-2',
      number: 'INV-000002',
      discount_amount: 500,
      discount_reason: 'Senior',
      total: 2000,
      amount_paid: 1200,
      payments: [
        { id: 'p1', amount: 1200, method: 'gcash', reference: '99887766', received_at: '2026-09-21T03:00:00Z' },
        { id: 'p2', amount: 300, method: 'cash', received_at: '2026-09-21T04:00:00Z', voided_at: '2026-09-21T05:00:00Z' },
      ],
    });
    const html = buildStatementHtml({
      clinic,
      patient,
      invoices: [paid, bill()],
      printedAt: new Date(2026, 8, 30, 10),
      logoSrc: (u) => u.replace('asset:', ''),
    });

    expect(html).toContain('D-Touch Dental Clinic');
    expect(html).toContain('Chart no. A-12');
    expect(html).toContain('Statement of account');
    // Names are escaped, not taken as markup.
    expect(html).toContain('Ana &lt;Cruz&gt;');
    expect(html).not.toContain('Ana <Cruz>');
    // The file name the PDF is offered under.
    expect(html).toContain('<title>Statement - Ana &lt;Cruz&gt; - 2026-09-30</title>');
    // Lines, visit and doctor.
    expect(html).toContain('Oral prophylaxis');
    expect(html).toContain('₱1,000');
    expect(html).toContain('Dr. Maria Santos');
    // Discount and the payment that stands, not the voided one.
    expect(html).toContain('Discount (Senior)');
    expect(html).toContain('GCash · ref 99887766');
    expect(html).not.toContain('₱300');
    // Totals over both bills: 2000 + 2500 charged, 1200 paid, 3300 due.
    expect(html).toContain('<td>Total charges (2 bills)</td><td>₱4,500</td>');
    expect(html).toContain('<td>Total paid</td><td>₱1,200</td>');
    expect(html).toContain('<td>Balance due</td><td>₱3,300</td>');
    expect(html).toContain('not an official receipt');
    expect(html).toContain('src="assets/brand/dtouch_mark.png"');
  });

  test('a fully paid statement is a payment summary; drafts are estimates, voided bills are left out', () => {
    expect(buildStatementHtml({ clinic, patient, invoices: [bill({ status: 'paid', amount_paid: 2500 })] })).toContain('Payment summary');
    const html = buildStatementHtml({
      clinic,
      patient,
      invoices: [bill({ id: 'd', status: 'draft', number: null }), bill({ id: 'v', status: 'void', number: 'INV-000009' })],
    });
    expect(html).toContain('Estimate');
    expect(html).toContain('Not yet issued');
    expect(html).toContain('may change');
    expect(html).not.toContain('INV-000009');
  });
});
