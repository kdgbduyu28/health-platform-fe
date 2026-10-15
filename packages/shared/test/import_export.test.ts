import { parseCsv, toCsv, unescapeCell } from '../src/import_export/csv';
import { DentalColumn, exportDentalCells, parseDentalCode, parseDentalStatus, parseSurfaces, parseTooth, readDentalRow } from '../src/import_export/dental_columns';
import { type DateOrder, parseImportDate, parseImportTime, parsePesos, parseYesNo, tidyName } from '../src/import_export/import_common';
import { PatientColumn, exportPatientCells, matchHeaders, readPatientRow } from '../src/import_export/patient_columns';
import { VisitColumn, exportVisitCells, matchDoctor, readVisitRow } from '../src/import_export/visit_columns';
import { decodeTextFile } from '../src/platform/browser';

const BOM = '﻿';
const rowJson = (headers: string[], cells: string[], order: DateOrder = 'month_first') => readPatientRow(cells, matchHeaders(headers), 2, order).json;
const day = (y: number, m: number, d: number) => new Date(y, m - 1, d);

describe('CSV', () => {
  test('reads quotes, commas, line breaks and doubled quotes', () => {
    const rows = parseCsv(`${BOM}Name,Notes\r\n"Cruz, Ana","Said ""hi""\nthen left"\r\nBen,\r\n,,\r\n`);
    expect(rows).toEqual([
      ['Name', 'Notes'],
      ['Cruz, Ana', 'Said "hi"\nthen left'],
      ['Ben', ''],
    ]);
  });

  test('reads a semicolon file from a comma-decimal Excel', () => {
    expect(parseCsv('Name;Balance\nAna;1,50\n')).toEqual([
      ['Name', 'Balance'],
      ['Ana', '1,50'],
    ]);
  });

  test('writes what it reads back, BOM first', () => {
    const rows = [
      ['Name', 'Notes', 'Phone'],
      ['Peña, Ana', 'Line one\nline "two"', '+63 917 555 0101'],
    ];
    const text = toCsv(rows);
    expect(text.startsWith(BOM)).toBe(true);
    expect(parseCsv(text)).toEqual(rows);
  });

  test('a formula is written as text and read back as typed', () => {
    const text = toCsv([['=HYPERLINK("x")', '-150', '@SUM(A1)']]);
    expect(text).toContain("'=HYPERLINK");
    expect(text).toContain(',-150,');
    const cells = parseCsv(text)[0];
    expect(unescapeCell(cells[0])).toBe('=HYPERLINK("x")');
    expect(unescapeCell(cells[1])).toBe('-150');
  });

  test('a Windows Excel file (not UTF-8) keeps its ñ', () => {
    expect(decodeTextFile(Uint8Array.from([...'Name\nPe', 0xf1, ...'a'].map((c) => (typeof c === 'string' ? c.charCodeAt(0) : c))))).toBe('Name\nPeña');
    expect(decodeTextFile(new TextEncoder().encode('Peña'))).toBe('Peña');
  });
});

describe('columns', () => {
  test('headers clinics use are recognised, each column once', () => {
    expect(matchHeaders(['Surname', 'First Name', 'Mobile No.', 'Birthdate', 'Gender', 'Remarks', 'Mobile', 'Favourite colour'])).toEqual([
      PatientColumn.lastName,
      PatientColumn.firstName,
      PatientColumn.phone,
      PatientColumn.dateOfBirth,
      PatientColumn.sex,
      PatientColumn.chartNote,
      null, // phone is taken
      null,
    ]);
  });

  test("an export's headers come back as the same columns", () => {
    const cols = PatientColumn.exported(true);
    const matched = matchHeaders(cols.map((c) => c.header));
    cols.forEach((c, i) => expect(matched[i], c.header).toBe(c.exportOnly ? null : c));
  });

  test("the front desk's export has no notes column", () => {
    expect(PatientColumn.exported(false)).not.toContain(PatientColumn.chartNote);
    expect(PatientColumn.template).not.toContain(PatientColumn.patientId);
  });
});

describe('values', () => {
  test('dates, either way round', () => {
    expect(parseImportDate('1990-04-03', 'day_first')).toEqual(day(1990, 4, 3));
    expect(parseImportDate('03/04/1990', 'month_first')).toEqual(day(1990, 3, 4));
    expect(parseImportDate('03/04/1990', 'day_first')).toEqual(day(1990, 4, 3));
    expect(parseImportDate('3/4/90', 'month_first')).toEqual(day(1990, 3, 4));
    expect(parseImportDate('March 4, 1990', 'day_first')).toEqual(day(1990, 3, 4));
    expect(parseImportDate('4 Mar 1990', 'month_first')).toEqual(day(1990, 3, 4));
    expect(parseImportDate('04/31/1990', 'month_first')).toBeNull();
    expect(parseImportDate('soon', 'month_first')).toBeNull();
  });

  test('names as clinics type them', () => {
    expect(tidyName('DELA CRUZ, JUAN')).toBe('Juan Dela Cruz');
    expect(tidyName('Juan dela Cruz, Jr.')).toBe('Juan dela Cruz, Jr.');
    expect(tidyName('  ana   peña ')).toBe('ana peña');
    expect(tidyName('MA. ÑORA')).toBe('Ma. Ñora');
  });

  test('yes and no, in English and Filipino; pesos however written', () => {
    expect(parseYesNo('Oo')).toBe(true);
    expect(parseYesNo('hindi')).toBe(false);
    expect(parseYesNo('maybe')).toBeNull();
    expect(parsePesos('₱1,500.50')).toBe(1500.5);
    expect(parsePesos('PHP 200')).toBe(200);
  });
});

describe('a patient row', () => {
  test('becomes the person, the form, the note and the balance', () => {
    const json = rowJson(
      ['Chart No.', 'Last name', 'First name', 'Mobile', 'Birthday', 'Sex', 'Medications', 'Allergies', 'Medical history', 'Under treatment', 'Signed by', 'Notes', 'Balance forwarded'],
      ['A-1', 'REYES', 'MARIA', '0917 555 0101', '07/22/1985', 'F', 'Losartan', 'Penicillin; lidocaine; shrimp', 'Hypertension, TB', 'no', 'Maria Reyes', 'Gag reflex', '₱1,500.50'],
    );
    expect(json.chart_number).toBe('A-1');
    expect(json.person).toEqual({ full_name: 'Maria Reyes', phone: '0917 555 0101', date_of_birth: '1985-07-22', sex: 'female' });
    const intake = json.intake;
    expect(intake.takes_medications, 'a medicine is named').toBe(true);
    expect(intake.under_treatment).toBe(false);
    expect(intake.allergies).toEqual(['penicillin', 'local_anesthetic']);
    expect(intake.allergies_other).toBe('shrimp');
    expect(intake.conditions).toEqual(['high_blood_pressure', 'tuberculosis']);
    expect(intake.signed_name).toBe('Maria Reyes');
    expect(json.chart_note).toBe('Gag reflex');
    expect(json.opening_balance).toBe('1500.50');
  });

  test('says what is wrong with it', () => {
    const r = readPatientRow(['', 'X', '13/13/2000', 'Rosa'], matchHeaders(['Name', 'Sex', 'Birthday', 'Guardian']), 7);
    expect(r.ok).toBe(false);
    expect(r.errors).toEqual(
      expect.arrayContaining([
        'Sex "X" is not Female or Male.',
        'Birthday "13/13/2000" is not a date.',
        'No name.',
        'A guardian needs a relationship (Parent or Guardian) and a phone.',
      ]),
    );
  });

  test('with no form columns filled, sends no form', () => {
    const json = rowJson(['Name', 'Allergies'], ['Ana Cruz', 'none']);
    expect('intake' in json).toBe(false);
    expect(json.person).toEqual({ full_name: 'Ana Cruz' });
  });

  test('an exported patient imports back as the same', () => {
    const intake = {
      under_treatment: false,
      takes_medications: true,
      medications: 'Losartan',
      allergies: ['latex'],
      conditions: ['diabetes'],
      guardian_name: 'Rosa Reyes',
      guardian_relationship: 'parent',
      guardian_phone: '0917',
      signed_name: 'Rosa Reyes',
      signed_on: '2024-05-06',
    };
    const exported = {
      patient_id: '30000000-0000-0000-0000-000000000002',
      chart_number: 'M-7',
      full_name: 'Maria Reyes',
      phone: '+63 928 123 4567',
      date_of_birth: '1985-07-22',
      sex: 'female',
      intake,
      chart_note: 'Gag reflex',
      balance: 250,
      completed_visits: 3,
    };
    const cols = PatientColumn.exported(true);
    const rows = parseCsv(toCsv([cols.map((c) => c.header), exportPatientCells(exported, cols)]));
    const back = readPatientRow(rows[1], matchHeaders(rows[0]), 2);
    expect(back.ok, back.errors.join()).toBe(true);
    expect(back.json.patient_id).toBe(exported.patient_id);
    expect(back.json.chart_number).toBe('M-7');
    expect(back.json.person).toEqual({ full_name: 'Maria Reyes', phone: '+63 928 123 4567', date_of_birth: '1985-07-22', sex: 'female' });
    expect(back.json.intake).toEqual(intake);
    expect(back.json.chart_note).toBe('Gag reflex');
    expect('opening_balance' in back.json, 'what they owe now is not an old balance to add').toBe(false);
  });
});

describe('visits', () => {
  test('times as clinics write them', () => {
    expect(parseImportTime('9:00')).toBe('09:00');
    expect(parseImportTime('9.30')).toBe('09:30');
    expect(parseImportTime('2 PM')).toBe('14:00');
    expect(parseImportTime('2:30pm')).toBe('14:30');
    expect(parseImportTime('12 am')).toBe('00:00');
    expect(parseImportTime('14:30')).toBe('14:30');
    expect(parseImportTime('9')).toBeNull();
    expect(parseImportTime('25:00')).toBeNull();
  });

  test('a doctor in a file is found on the roster', () => {
    const roster = new Map([
      ['Maria Santos', 'd1'],
      ['Jose Reyes', 'd2'],
      ['Ana Santos', 'd3'],
    ]);
    expect(matchDoctor('Dra. Maria Santos', roster)).toBe('d1');
    expect(matchDoctor('REYES', roster)).toBe('d2');
    expect(matchDoctor('Santos', roster), 'two Santoses').toBeNull();
    expect(matchDoctor('Dr. Lim', roster)).toBeNull();
  });

  test('a row becomes the visit', () => {
    const headers = ['Chart No.', 'Patient Name', 'Date of Visit', 'Time', 'Dentist', 'Procedure', 'Remarks', 'Status'];
    const r = readVisitRow(
      ['A-1', 'REYES, MARIA', '01/10/2023', '2:30 PM', 'Dra. Santos', 'Oral prophylaxis', 'Bleeding gums', 'done'],
      VisitColumn.match(headers),
      2,
      new Map([['Dra. Santos', 'd1']]),
    );
    expect(r.ok, r.errors.join()).toBe(true);
    expect(r.json).toEqual({
      row: 2,
      chart_number: 'A-1',
      patient_name: 'Maria Reyes',
      date: '2023-01-10',
      time: '14:30',
      doctor_id: 'd1',
      service: 'Oral prophylaxis',
      visit_note: 'Bleeding gums',
      status: 'completed',
    });
  });

  test('says what is wrong with a row', () => {
    const r = readVisitRow(['', '31/31/2023', 'Dr. Who', 'soon', 'later'], VisitColumn.match(['Patient', 'Date', 'Doctor', 'Time', 'Status']), 3, new Map());
    expect(r.errors).toEqual([
      'No patient: give a chart number or a name.',
      'Date "31/31/2023" is not a date.',
      'Time "soon" is not a time.',
      'Doctor "Dr. Who" is not matched to anyone on the roster.',
      'Status "later" is not Completed, Cancelled, No-show, Pending or Confirmed.',
    ]);
  });

  test('an export imports back', () => {
    const cols = VisitColumn.exported(true);
    const text = toCsv([
      cols.map((c) => c.header),
      exportVisitCells(
        {
          patient_id: '30000000-0000-0000-0000-000000000001',
          chart_number: null,
          patient_name: 'Juan dela Cruz',
          date: '2023-01-10',
          time: '09:00',
          doctor: 'Maria Santos',
          service: 'Teeth Cleaning',
          duration_minutes: 45,
          status: 'no_show',
          visit_note: null,
          patient_note: null,
        },
        cols,
      ),
    ]);
    const rows = parseCsv(text);
    const back = readVisitRow(rows[1], VisitColumn.match(rows[0]), 2, new Map([['Maria Santos', 'd1']]));
    expect(back.ok, back.errors.join()).toBe(true);
    expect(back.json.status).toBe('no_show');
    expect(back.json.patient_id).toBe('30000000-0000-0000-0000-000000000001');
    expect(back.json.time).toBe('09:00');
    expect(back.json.duration_minutes).toBe(45);
  });
});

describe('dental chart', () => {
  test('teeth in either numbering, as FDI', () => {
    expect(parseTooth('16', 'fdi')).toBe(16);
    expect(parseTooth('#3', 'universal')).toBe(16);
    expect(parseTooth('30', 'universal')).toBe(46);
    expect(parseTooth('A', 'fdi')).toBe(55);
    expect(parseTooth('19', 'fdi')).toBeNull();
    expect(parseTooth('33', 'universal')).toBeNull();
  });

  test('surfaces, codes and statuses as dentists write them', () => {
    expect(parseSurfaces('MOD')).toEqual(['D', 'M', 'O']);
    expect(parseSurfaces('incisal, facial')).toEqual(['B', 'O']);
    expect(parseSurfaces('MX')).toBeNull();
    expect(parseDentalCode('RCT')).toBe('root_canal');
    expect(parseDentalCode('Pasta')).toBe('filling');
    expect(parseDentalCode('Decay')).toBe('caries');
    expect(parseDentalCode('Jacket crown')).toBe('crown');
    expect(parseDentalCode('braces')).toBeNull();
    expect(parseDentalStatus('On exam')).toBe('existing');
    expect(parseDentalStatus('to do')).toBe('planned');
  });

  test('a row becomes a chart entry; an export comes back the same', () => {
    const cols = DentalColumn.exported;
    const text = toCsv([
      cols.map((c) => c.header),
      exportDentalCells(
        {
          patient_id: null,
          chart_number: 'A-1',
          patient_name: 'Maria Reyes',
          tooth: 16,
          surfaces: 'MO',
          code: 'root_canal',
          status: 'done',
          date: '2023-01-10',
          note: 'Two canals',
        },
        cols,
      ),
    ]);
    const rows = parseCsv(text);
    expect(rows[1].slice(4, 7)).toEqual(['MO', 'Root canal', 'Done']);
    const back = readDentalRow(rows[1], DentalColumn.match(rows[0]), 2);
    expect(back.ok, back.errors.join()).toBe(true);
    expect(back.json).toEqual({
      row: 2,
      chart_number: 'A-1',
      patient_name: 'Maria Reyes',
      tooth: 16,
      code: 'root_canal',
      surfaces: ['M', 'O'],
      status: 'done',
      date: '2023-01-10',
      note: 'Two canals',
    });
  });
});
