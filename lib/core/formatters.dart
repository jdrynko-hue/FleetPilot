String formatDate(DateTime? value) {
  if (value == null) return '—';
  final d = value.toLocal();
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

String formatDateTime(DateTime? value) {
  if (value == null) return '—';
  final d = value.toLocal();
  return '${formatDate(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

String formatMileage(num? value) {
  if (value == null) return '—';
  final digits = value.round().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

String formatMoney(num value, {String currency = 'GBP'}) {
  final symbol = switch (currency.toUpperCase()) {
    'GBP' => '£',
    'EUR' => '€',
    'USD' => r'$',
    'PLN' => 'zł ',
    _ => '$currency ',
  };
  return '$symbol${value.toStringAsFixed(2)}';
}

DateTime? parseDate(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}

int? parseInt(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  return int.tryParse(trimmed.replaceAll(',', ''));
}

double parseMoneyInput(String value) {
  final normalized = value.trim().replaceAll(',', '.');
  return double.tryParse(normalized) ?? 0;
}
