import '../auth/billing_markets.dart';

/// Garage billing follows the workshop country: UK GBP, Poland PLN, all other
/// EU members EUR (including members whose domestic currency is not the euro).
const supportedGarageCountries = <String, String>{
  ...supportedFleetCountries,
  'CZ': 'Czechia', 'DK': 'Denmark', 'HU': 'Hungary',
  'RO': 'Romania', 'SE': 'Sweden',
};

const _additionalNamesPl = <String, String>{
  'CZ': 'Czechy', 'DK': 'Dania', 'HU': 'Węgry',
  'RO': 'Rumunia', 'SE': 'Szwecja',
};

String garageCountryName(String code, {String locale = 'en'}) =>
    (locale == 'pl' ? {...fleetCountryNamesPl, ..._additionalNamesPl}
      : supportedGarageCountries)[code] ?? code;

String? currencyForGarageCountry(String countryCode) {
  final code = countryCode.trim().toUpperCase();
  if (code == 'GB') return 'GBP';
  if (code == 'PL') return 'PLN';
  return supportedGarageCountries.containsKey(code) ? 'EUR' : null;
}
