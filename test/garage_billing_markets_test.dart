import 'package:flutter_test/flutter_test.dart';
import 'package:fleetpilot/garage/billing_markets.dart';

void main() {
  const eu = ['AT','BE','BG','HR','CY','CZ','DK','EE','FI','FR','DE','GR','HU',
    'IE','IT','LV','LT','LU','MT','NL','PL','PT','RO','SK','SI','ES','SE'];
  test('Garage supports UK and all 27 EU countries', () {
    expect(supportedGarageCountries.keys.toSet(), {'GB', ...eu});
    expect(currencyForGarageCountry('GB'), 'GBP');
    expect(currencyForGarageCountry(' pl '), 'PLN');
    for (final country in eu.where((code) => code != 'PL')) {
      expect(currencyForGarageCountry(country), 'EUR', reason: country);
    }
    for (final country in ['US', 'CH', 'NO', 'unknown', '']) {
      expect(currencyForGarageCountry(country), isNull);
    }
  });
  test('additional EU countries have English and Polish names', () {
    for (final country in ['CZ','DK','HU','RO','SE']) {
      expect(garageCountryName(country), isNot(country));
      expect(garageCountryName(country, locale: 'pl'), isNot(country));
    }
  });
}
