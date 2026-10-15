/// CSV as spreadsheets write it (RFC 4180): quoted fields may hold commas,
/// line breaks and doubled quotes.
///
/// Reading takes what Excel and Google Sheets save: a UTF-8 byte order mark,
/// CRLF or LF line ends, and a semicolon instead of a comma where the
/// computer's region uses the comma for decimals. Writing produces what Excel
/// opens correctly: a BOM (without it Excel reads "Peña" as "PeÃ±a") and CRLF.

const bom = '﻿';

/// The rows of [text], every row a list of fields. Blank rows are dropped.
export function parseCsv(input: string): string[][] {
  const text = input.startsWith(bom) ? input.substring(1) : input;
  const delimiter = guessDelimiter(text);
  const rows: string[][] = [];
  let row: string[] = [];
  let field = '';
  let quoted = false;

  const endField = () => {
    row.push(field);
    field = '';
  };
  const endRow = () => {
    endField();
    // A spreadsheet's trailing ",,,," rows are blank too.
    if (row.some((f) => f.trim() !== '')) rows.push(row);
    row = [];
  };

  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (quoted) {
      if (c === '"') {
        if (i + 1 < text.length && text[i + 1] === '"') {
          field += '"';
          i++;
          continue;
        }
        quoted = false;
      } else {
        field += c;
      }
    } else if (c === '"' && field === '') {
      quoted = true;
    } else if (c === delimiter) {
      endField();
    } else if (c === '\r' || c === '\n') {
      endRow();
      if (c === '\r' && i + 1 < text.length && text[i + 1] === '\n') i++;
    } else {
      field += c;
    }
  }
  if (field !== '' || row.length > 0) endRow();
  return rows;
}

/// Comma, unless the header line has more semicolons (or tabs) outside
/// quotes than commas.
function guessDelimiter(text: string): string {
  const counts: Record<string, number> = { ',': 0, ';': 0, '\t': 0 };
  let quoted = false;
  for (const c of text) {
    if (c === '"') quoted = !quoted;
    if (quoted) continue;
    if (c === '\n' || c === '\r') break;
    if (c in counts) counts[c]++;
  }
  let best = ',';
  for (const [k, v] of Object.entries(counts)) if (v > counts[best]) best = k;
  return best;
}

/// [rows] as a CSV file's text, BOM first. Null writes an empty field.
export function toCsv(rows: readonly (readonly unknown[])[]): string {
  let out = bom;
  for (const row of rows) out += `${row.map(escape).join(',')}\r\n`;
  return out;
}

function escape(value: unknown): string {
  const s = value == null ? '' : String(value);
  // A leading =, +, - or @ makes a spreadsheet run the cell as a formula
  // (CSV injection). Patient data is typed by the public, so an apostrophe
  // keeps it text; [unescapeCell] takes it off again on import. A phone
  // number or amount ("+63 917…", "-150") is left alone.
  const safe = looksLikeFormula(s) ? `'${s}` : s;
  return /[",\r\n;]/.test(safe) ? `"${safe.replace(/"/g, '""')}"` : safe;
}

function looksLikeFormula(s: string): boolean {
  if (s === '') return false;
  if (s[0] === '=' || s[0] === '@') return true;
  return (s[0] === '+' || s[0] === '-') && !/^[+-][\d\s().,-]*$/.test(s);
}

/// A cell as typed, without the apostrophe [toCsv] put in front of a
/// formula-looking value.
export function unescapeCell(cell: string): string {
  return cell.length > 1 && cell[0] === "'" && looksLikeFormula(cell.substring(1)) ? cell.substring(1) : cell;
}
