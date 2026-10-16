import '../core/localization.dart';

String uncertainFleetCreation() => const {
  'en': 'The result is uncertain. Check your fleet list before trying again.',
  'pl': 'Wynik jest niepewny. Sprawdź listę flot przed kolejną próbą.',
  'de': 'Das Ergebnis ist unklar. Prüfen Sie vor einem neuen Versuch Ihre Flottenliste.',
  'sk': 'Výsledok je neistý. Pred ďalším pokusom skontrolujte zoznam flotíl.',
  'cs': 'Výsledek je nejistý. Před dalším pokusem zkontrolujte seznam flotil.',
  'hu': 'Az eredmény bizonytalan. Újabb próbálkozás előtt ellenőrizze a flották listáját.',
  'ro': 'Rezultatul este incert. Verifică lista flotelor înainte de a încerca din nou.',
  'es': 'El resultado es incierto. Revisa tus flotas antes de volver a intentarlo.',
  'fr': 'Le résultat est incertain. Vérifiez vos flottes avant de réessayer.',
  'it': 'Il risultato è incerto. Controlla le flotte prima di riprovare.',
  'uk': 'Результат невизначений. Перевірте список автопарків перед повторною спробою.',
  'pt': 'O resultado é incerto. Verifique as frotas antes de tentar novamente.',
}[AppLocale.language.value] ?? 'The result is uncertain. Check your fleet list before trying again.';
