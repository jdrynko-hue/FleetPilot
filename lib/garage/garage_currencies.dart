/// Supported workshop estimate currencies and their ISO 4217 minor units.
///
/// Payment checkout currencies are a separate Stripe configuration. Adding a
/// quote currency does NOT enable accepting subscriptions in that currency.
/// Amounts remain integer minor units; no implicit exchange rates are used.
class GarageCurrencies {
  const GarageCurrencies._();

  static const Map<String, int> fractionDigits = {
    'GBP': 2, 'EUR': 2, 'PLN': 2,
    'USD': 2, 'CHF': 2, 'CZK': 2, 'SEK': 2, 'NOK': 2,
    'DKK': 2, 'HUF': 2, 'RON': 2,
    'CAD': 2, 'AUD': 2, 'NZD': 2, 'UAH': 2,
    'AED': 2, 'INR': 2, 'BRL': 2, 'ZAR': 2,
    'SGD': 2, 'TRY': 2, 'MXN': 2, 'ILS': 2,
    'THB': 2, 'HKD': 2,
    'JPY': 0, 'KRW': 0, 'ISK': 0,
    'KWD': 3, 'BHD': 3, 'OMR': 3,
  };

  static const preferred = ['GBP', 'EUR', 'PLN'];

  static List<String> get others => fractionDigits.keys
      .where((code) => !preferred.contains(code)).toList(growable: false);

  static int digits(String currency) {
    final value = fractionDigits[currency];
    if (value == null) {
      throw FormatException('Unsupported ISO currency: $currency');
    }
    return value;
  }

  static String formatMinor(String currency, int minor) {
    if (minor < 0) {
      throw const FormatException('Negative money amount not allowed');
    }
    final precision = digits(currency);
    var divisor = 1;
    for (var i = 0; i < precision; i++) {
      divisor *= 10;
    }
    final major = (minor ~/ divisor).toString();
    final remainder = precision == 0
        ? ''
        : '.${(minor % divisor).toString().padLeft(precision, '0')}';
    return switch (currency) {
      'GBP' => '£$major$remainder',
      'EUR' => '€$major$remainder',
      'PLN' => '$major,${(minor % 100).toString().padLeft(2, '0')} zł',
      _ => '$currency $major$remainder',
    };
  }
}
