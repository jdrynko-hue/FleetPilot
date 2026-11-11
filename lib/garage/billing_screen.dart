import 'package:flutter/material.dart';

import '../core/localization.dart';

/// Garage billing has its own rollout. Never opens Fleet checkout or infers a
/// subscription from workshop creation. Server-backed billing will replace the
/// availability notice once its independent owner ACL and webhooks are ready.
class GarageBillingScreen extends StatelessWidget {
  const GarageBillingScreen({required this.workshopName,
    required this.isOwner, super.key});

  final String workshopName;
  final bool isOwner;

  static const translations = <String, List<String>>{
    'en': ['Subscription and payments', 'Only the workshop owner can manage billing.', 'Payments are not available yet', 'Garage subscriptions are being prepared. You cannot purchase a plan or enter payment details here yet.', 'Fixed subscription, no booking commission', 'Creating a workshop does not start a paid subscription. Fleet subscriptions are separate from Garage.'],
    'pl': ['Subskrypcja i płatności', 'Tylko właściciel warsztatu może zarządzać płatnościami.', 'Płatności nie są jeszcze dostępne', 'Przygotowujemy abonamenty Garage. Nie możesz tu jeszcze kupić planu ani podać danych płatniczych.', 'Stały abonament, bez prowizji od rezerwacji', 'Utworzenie warsztatu nie uruchamia płatnego abonamentu. Subskrypcje Fleet są oddzielne od Garage.'],
    'de': ['Abonnement und Zahlungen', 'Nur der Werkstattinhaber kann Zahlungen verwalten.', 'Zahlungen sind noch nicht verfügbar', 'Garage-Abonnements werden vorbereitet. Sie können hier noch keinen Tarif kaufen oder Zahlungsdaten eingeben.', 'Festes Abonnement, keine Buchungsprovision', 'Die Erstellung einer Werkstatt startet kein kostenpflichtiges Abonnement. Fleet-Abonnements sind von Garage getrennt.'],
    'sk': ['Predplatné a platby', 'Platby môže spravovať iba vlastník servisu.', 'Platby zatiaľ nie sú dostupné', 'Predplatné Garage pripravujeme. Zatiaľ tu nemôžete kúpiť plán ani zadať platobné údaje.', 'Pevné predplatné bez provízie za rezervácie', 'Vytvorenie servisu nespustí platené predplatné. Predplatné Fleet je oddelené od Garage.'],
    'cs': ['Předplatné a platby', 'Platby může spravovat pouze vlastník servisu.', 'Platby zatím nejsou dostupné', 'Předplatné Garage připravujeme. Zatím zde nemůžete koupit plán ani zadat platební údaje.', 'Pevné předplatné bez provize za rezervace', 'Vytvoření servisu nespustí placené předplatné. Předplatné Fleet je oddělené od Garage.'],
    'hu': ['Előfizetés és fizetés', 'Csak a műhely tulajdonosa kezelheti a fizetéseket.', 'A fizetés még nem érhető el', 'A Garage előfizetései előkészületben vannak. Itt még nem vásárolhat csomagot és nem adhat meg fizetési adatokat.', 'Fix előfizetés, foglalási jutalék nélkül', 'A műhely létrehozása nem indít fizetős előfizetést. A Fleet és a Garage előfizetése különálló.'],
    'ro': ['Abonament și plăți', 'Doar proprietarul atelierului poate gestiona plățile.', 'Plățile nu sunt încă disponibile', 'Pregătim abonamentele Garage. Încă nu puteți cumpăra un plan sau introduce date de plată aici.', 'Abonament fix, fără comision pentru rezervări', 'Crearea unui atelier nu pornește un abonament plătit. Abonamentele Fleet sunt separate de Garage.'],
    'es': ['Suscripción y pagos', 'Solo el propietario del taller puede gestionar los pagos.', 'Los pagos aún no están disponibles', 'Estamos preparando las suscripciones de Garage. Todavía no puede comprar un plan ni introducir datos de pago aquí.', 'Suscripción fija, sin comisión por reservas', 'Crear un taller no inicia una suscripción de pago. Las suscripciones de Fleet son independientes de Garage.'],
    'fr': ['Abonnement et paiements', 'Seul le propriétaire de l’atelier peut gérer les paiements.', 'Les paiements ne sont pas encore disponibles', 'Les abonnements Garage sont en préparation. Vous ne pouvez pas encore acheter de forfait ni saisir vos données de paiement ici.', 'Abonnement fixe, sans commission sur les réservations', 'Créer un atelier ne déclenche pas d’abonnement payant. Les abonnements Fleet sont distincts de Garage.'],
    'it': ['Abbonamento e pagamenti', 'Solo il proprietario dell’officina può gestire i pagamenti.', 'I pagamenti non sono ancora disponibili', 'Stiamo preparando gli abbonamenti Garage. Non è ancora possibile acquistare un piano o inserire dati di pagamento qui.', 'Abbonamento fisso, senza commissioni sulle prenotazioni', 'Creare un’officina non avvia un abbonamento a pagamento. Gli abbonamenti Fleet sono separati da Garage.'],
    'uk': ['Підписка та платежі', 'Лише власник майстерні може керувати платежами.', 'Платежі ще недоступні', 'Ми готуємо підписки Garage. Тут ще не можна придбати план або ввести платіжні дані.', 'Фіксована підписка без комісії за бронювання', 'Створення майстерні не запускає платну підписку. Підписки Fleet відокремлені від Garage.'],
    'pt': ['Subscrição e pagamentos', 'Só o proprietário da oficina pode gerir os pagamentos.', 'Os pagamentos ainda não estão disponíveis', 'Estamos a preparar as subscrições Garage. Ainda não pode comprar um plano ou introduzir dados de pagamento aqui.', 'Subscrição fixa, sem comissão por reservas', 'Criar uma oficina não inicia uma subscrição paga. As subscrições Fleet são separadas do Garage.'],
  };

  static String text(int index) =>
      (translations[AppLocale.language.value] ?? translations['en']!)[index];

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String>(
    valueListenable: AppLocale.language,
    builder: (context, _, child) => Scaffold(
      appBar: AppBar(title: Text(text(0))),
      body: !isOwner ? Center(child: Padding(
        padding: const EdgeInsets.all(24), child: Text(text(1)))) :
        ListView(padding: const EdgeInsets.all(16), children: [
          Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(workshopName, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              Card(child: Padding(padding: const EdgeInsets.all(20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.credit_card_off_outlined),
                  const SizedBox(height: 12),
                  Text(text(2), style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12), Text(text(3)),
                ]))),
              const SizedBox(height: 12),
              Card(child: Padding(padding: const EdgeInsets.all(20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(text(4), style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12), Text(text(5)),
                ]))),
            ]))),
        ]),
    ),
  );
}
