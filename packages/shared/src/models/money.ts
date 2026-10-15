/// `₱1,500` or `₱1,500.50` — whole pesos drop the centavos.
export function formatPeso(amount: number): string {
  const negative = amount < 0;
  const p = Math.abs(amount);
  const whole = p === Math.round(p);
  const digits = p.toFixed(whole ? 0 : 2);
  const parts = digits.split('.');
  const grouped = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, ',');
  return `${negative ? '-' : ''}₱${grouped}${parts.length > 1 ? `.${parts[1]}` : ''}`;
}

/// Postgres `numeric` arrives as a JSON number — or, from some paths, a
/// string. Either way, a number.
export function parseMoney(value: unknown): number {
  if (value == null) return 0;
  if (typeof value === 'number') return value;
  if (typeof value === 'string') {
    const n = Number(value);
    if (Number.isNaN(n)) throw new Error(`not an amount: ${value}`);
    return n;
  }
  throw new Error(`not an amount: ${String(value)}`);
}
