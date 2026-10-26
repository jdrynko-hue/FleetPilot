/// Editable capital/mainland suggestion only. Countries may span time zones;
/// owners must choose the workshop's actual IANA zone before saving.
const workshopTimeZoneSuggestions = <String, String>{
  'GB': 'Europe/London', 'PL': 'Europe/Warsaw', 'AT': 'Europe/Vienna',
  'BE': 'Europe/Brussels', 'BG': 'Europe/Sofia', 'HR': 'Europe/Zagreb',
  'CY': 'Asia/Nicosia', 'EE': 'Europe/Tallinn', 'FI': 'Europe/Helsinki',
  'FR': 'Europe/Paris', 'DE': 'Europe/Berlin', 'GR': 'Europe/Athens',
  'IE': 'Europe/Dublin', 'IT': 'Europe/Rome', 'LV': 'Europe/Riga',
  'LT': 'Europe/Vilnius', 'LU': 'Europe/Luxembourg', 'MT': 'Europe/Malta',
  'NL': 'Europe/Amsterdam', 'PT': 'Europe/Lisbon', 'SK': 'Europe/Bratislava',
  'SI': 'Europe/Ljubljana', 'ES': 'Europe/Madrid',
  'CZ': 'Europe/Prague', 'DK': 'Europe/Copenhagen', 'HU': 'Europe/Budapest',
  'RO': 'Europe/Bucharest', 'SE': 'Europe/Stockholm',
};

String suggestedWorkshopTimeZone(String? country) =>
  workshopTimeZoneSuggestions[country?.trim().toUpperCase()] ?? 'Europe/London';
