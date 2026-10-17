import '../core/localization.dart';

/// Describes the persisted listing preference, not slot availability or approval.
class BookingVisibilityText {
  static const translations = <String, List<String>>{
    'en': ['Saved setting: workshop listing disabled.', 'Saved setting: workshop listing enabled.'],
    'pl': ['Zapisane ustawienie: wyświetlanie warsztatu wyłączone.', 'Zapisane ustawienie: wyświetlanie warsztatu włączone.'],
    'de': ['Gespeicherte Einstellung: Werkstatteintrag deaktiviert.', 'Gespeicherte Einstellung: Werkstatteintrag aktiviert.'],
    'sk': ['Uložené nastavenie: zobrazenie dielne vypnuté.', 'Uložené nastavenie: zobrazenie dielne zapnuté.'],
    'cs': ['Uložené nastavení: zobrazení dílny vypnuto.', 'Uložené nastavení: zobrazení dílny zapnuto.'],
    'hu': ['Mentett beállítás: műhely megjelenítése kikapcsolva.', 'Mentett beállítás: műhely megjelenítése bekapcsolva.'],
    'ro': ['Setare salvată: afișarea atelierului dezactivată.', 'Setare salvată: afișarea atelierului activată.'],
    'es': ['Configuración guardada: publicación del taller desactivada.', 'Configuración guardada: publicación del taller activada.'],
    'fr': ['Paramètre enregistré : affichage de l’atelier désactivé.', 'Paramètre enregistré : affichage de l’atelier activé.'],
    'it': ['Impostazione salvata: visibilità officina disattivata.', 'Impostazione salvata: visibilità officina attivata.'],
    'uk': ['Збережене налаштування: показ майстерні вимкнено.', 'Збережене налаштування: показ майстерні ввімкнено.'],
    'pt': ['Definição guardada: apresentação da oficina desativada.', 'Definição guardada: apresentação da oficina ativada.'],
  };
  static String saved(bool listed) =>
    (translations[AppLocale.language.value] ?? translations['en']!)[listed ? 1 : 0];
}
