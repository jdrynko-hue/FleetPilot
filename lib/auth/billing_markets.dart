/// Supported billing markets for new Flotaryx fleets.
///
/// Must remain aligned with the create_company_for_current_user database RPC.
/// Never enable a new country here without matching backend pricing support.
const supportedFleetCountries = <String, String>{
  'GB': 'United Kingdom',
  'PL': 'Poland',
  'AT': 'Austria',
  'BE': 'Belgium',
  'BG': 'Bulgaria',
  'HR': 'Croatia',
  'CY': 'Cyprus',
  'EE': 'Estonia',
  'FI': 'Finland',
  'FR': 'France',
  'DE': 'Germany',
  'GR': 'Greece',
  'IE': 'Ireland',
  'IT': 'Italy',
  'LV': 'Latvia',
  'LT': 'Lithuania',
  'LU': 'Luxembourg',
  'MT': 'Malta',
  'NL': 'Netherlands',
  'PT': 'Portugal',
  'SK': 'Slovakia',
  'SI': 'Slovenia',
  'ES': 'Spain',
};

const fleetCountryNamesPl = <String, String>{
  'GB': 'Wielka Brytania',
  'PL': 'Polska',
  'AT': 'Austria',
  'BE': 'Belgia',
  'BG': 'Bułgaria',
  'HR': 'Chorwacja',
  'CY': 'Cypr',
  'EE': 'Estonia',
  'FI': 'Finlandia',
  'FR': 'Francja',
  'DE': 'Niemcy',
  'GR': 'Grecja',
  'IE': 'Irlandia',
  'IT': 'Włochy',
  'LV': 'Łotwa',
  'LT': 'Litwa',
  'LU': 'Luksemburg',
  'MT': 'Malta',
  'NL': 'Holandia',
  'PT': 'Portugalia',
  'SK': 'Słowacja',
  'SI': 'Słowenia',
  'ES': 'Hiszpania',
};

String fleetCountryName(String countryCode, {String locale = 'en'}) =>
    (locale == 'pl' ? fleetCountryNamesPl : supportedFleetCountries)[countryCode] ??
    countryCode;

String? currencyForFleetCountry(String countryCode) {
  final code = countryCode.trim().toUpperCase();
  if (code == 'GB') return 'GBP';
  if (code == 'PL') return 'PLN';
  if (supportedFleetCountries.containsKey(code)) return 'EUR';
  return null;
}
