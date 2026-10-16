import 'localization.dart';

/// Fleet repair columns are NUMERIC(12,2). Empty optional costs remain zero.
/// Reject ambiguous grouping, currency text, exponents and non-finite values.
double parseMoneyInput(String value) {
  final text = value.trim();
  if (text.isEmpty) return 0;
  if (!RegExp(r'^(?:[0-9]{1,10}(?:[.,][0-9]{1,2})?|[.,][0-9]{1,2})$').hasMatch(text)) {
    throw const FormatException('Invalid repair cost');
  }
  return double.parse(text.replaceAll(',', '.'));
}

String? validateMoneyInput(String? value, {String? locale}) {
  try {
    parseMoneyInput(value ?? '');
    return null;
  } on FormatException {
    return const {
      'en': 'Invalid amount (max. 2 decimals).',
      'pl': 'Nieprawidłowa kwota (maks. 2 miejsca).',
      'de': 'Ungültiger Betrag (max. 2 Dezimalstellen).',
      'sk': 'Neplatná suma (max. 2 desatinné miesta).',
      'cs': 'Neplatná částka (max. 2 desetinná místa).',
      'hu': 'Érvénytelen összeg (max. 2 tizedesjegy).',
      'ro': 'Sumă invalidă (max. 2 zecimale).',
      'es': 'Importe no válido (máx. 2 decimales).',
      'fr': 'Montant invalide (max. 2 décimales).',
      'it': 'Importo non valido (max. 2 decimali).',
      'uk': 'Некоректна сума (макс. 2 знаки).',
      'pt': 'Valor inválido (máx. 2 casas decimais).',
    }[locale ?? AppLocale.language.value] ?? 'Invalid amount (max. 2 decimals).';
  }
}
