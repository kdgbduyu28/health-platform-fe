import { describe, expect, it } from 'vitest';

import { ClinicReport, clinicReportCsvRows, formatRate } from '../src/models/clinic_report';
import { parseCsv, toCsv } from '../src/import_export/csv';

const json = {
  from: '2026-10-01',
  to: '2026-10-02',
  visits: { total: 10, by_status: { completed: 6, no_show: 2, cancelled: 1, confirmed: 1 } },
  by_day: [
    { day: '2026-10-01', visits: 5, completed: 3, no_shows: 1, paid: '1500.50' },
    { day: '2026-10-02', visits: 4, completed: 3, no_shows: 1, paid: 0 },
  ],
  by_doctor: [{ doctor_id: 'd1', name: 'Dr. Santos', visits: 9, completed: 6, no_shows: 2, cancelled: 1, billed: '4200.00' }],
  by_service: [{ name: 'Root Canal', completed: 2, quantity: 2, amount: '3000.00' }],
  new_patients: 3,
  billed: '4200.00',
  discounts: '300.00',
  bill_count: 4,
  paid: '1500.50',
};

describe('ClinicReport', () => {
  const r = ClinicReport.fromJson(json);

  it('reads every block', () => {
    expect(r.from).toEqual(new Date(2026, 9, 1));
    expect(r.visitTotal).toBe(10);
    expect(r.count('completed')).toBe(6);
    expect(r.count('arrived')).toBe(0);
    expect(r.byDay[0].paid).toBe(1500.5);
    expect(r.byDoctor[0].billed).toBe(4200);
    expect(r.byService[0].amount).toBe(3000);
    expect([r.newPatients, r.billed, r.discounts, r.billCount, r.paid]).toEqual([3, 4200, 300, 4, 1500.5]);
  });

  it('leaves cancelled visits out of the visit count', () => {
    expect(r.visits).toBe(9);
  });

  it('measures no-shows against visits whose outcome is known', () => {
    // 2 no-shows out of 6 completed + 2 no-shows; the confirmed one is open.
    expect(r.noShowRate).toBe(0.25);
    expect(formatRate(r.noShowRate)).toBe('25%');
  });

  it('has no rate before any visit is settled', () => {
    const empty = ClinicReport.fromJson({ from: '2026-10-01', to: '2026-10-01', visits: { total: 0, by_status: {} } });
    expect(empty.noShowRate).toBeNull();
    expect(formatRate(empty.noShowRate)).toBe('—');
    expect(empty.byDay).toEqual([]);
  });

  it('exports as one CSV with a block per table', () => {
    const rows = parseCsv(toCsv(clinicReportCsvRows(r)));
    expect(rows[0]).toEqual(['Report', '2026-10-01 to 2026-10-02']);
    expect(rows).toContainEqual(['No-show rate', '25%']);
    expect(rows).toContainEqual(['2026-10-01', '5', '3', '1', '1500.50']);
    expect(rows).toContainEqual(['Dr. Santos', '9', '6', '2', '1', '4200.00']);
    expect(rows).toContainEqual(['Root Canal', '2', '2', '3000.00']);
  });
});
