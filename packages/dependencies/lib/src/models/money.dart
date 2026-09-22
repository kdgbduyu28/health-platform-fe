/// `₱1,500` or `₱1,500.50` — whole pesos drop the centavos.
String formatPeso(num amount) {
  final negative = amount < 0;
  final p = amount.abs().toDouble();
  final whole = p == p.roundToDouble();
  final digits = p.toStringAsFixed(whole ? 0 : 2);
  final parts = digits.split('.');
  final grouped = parts.first
      .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  return '${negative ? '-' : ''}₱$grouped'
      '${parts.length > 1 ? '.${parts[1]}' : ''}';
}

/// Postgres `numeric` arrives as a JSON number — or, from some paths, a
/// string. Either way, a double.
double parseMoney(Object? value) => switch (value) {
      null => 0,
      num n => n.toDouble(),
      String s => double.parse(s),
      _ => throw FormatException('not an amount: $value'),
    };
