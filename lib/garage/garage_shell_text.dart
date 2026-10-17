import '../core/localization.dart';

/// Short tab labels; detailed screen titles stay in GarageUiText.
class GarageShellText {
  static const translations = <String, List<String>>{
    'en': ['Calendar', 'Orders', 'Requests'],
    'pl': ['Kalendarz', 'Zlecenia', 'Zgłoszenia'],
    'de': ['Kalender', 'Aufträge', 'Anfragen'],
    'sk': ['Kalendár', 'Zákazky', 'Žiadosti'],
    'cs': ['Kalendář', 'Zakázky', 'Žádosti'],
    'hu': ['Naptár', 'Munkalapok', 'Kérelmek'],
    'ro': ['Calendar', 'Comenzi', 'Cereri'],
    'es': ['Calendario', 'Órdenes', 'Solicitudes'],
    'fr': ['Calendrier', 'Ordres', 'Demandes'],
    'it': ['Calendario', 'Ordini', 'Richieste'],
    'uk': ['Календар', 'Замовлення', 'Заявки'],
    'pt': ['Calendário', 'Ordens', 'Pedidos'],
  };
  static String tab(int index) =>
      (translations[AppLocale.language.value] ?? translations['en']!)[index];
}
