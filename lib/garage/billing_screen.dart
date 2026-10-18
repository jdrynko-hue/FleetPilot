import 'dart:async';

import 'package:flutter/material.dart';

import '../core/localization.dart';
import 'entitlement_repository.dart';

typedef GarageEntitlementLoader = Future<GarageEntitlementRead> Function();

/// Garage billing has its own rollout. Never opens Fleet checkout or infers a
/// subscription from workshop creation. The optional Sandbox status comes only
/// from the member-checked server entitlement; purchase controls stay disabled.
class GarageBillingScreen extends StatefulWidget {
  const GarageBillingScreen({required this.workshopName,
    required this.isOwner, this.workspaceId, this.loadEntitlement,
    this.now, super.key});

  final String workshopName;
  final bool isOwner;
  // Keep owner-only server decisions scoped to the workshop being displayed.
  final String? workspaceId;
  final GarageEntitlementLoader? loadEntitlement;
  // Injectable clock keeps expiry boundary tests deterministic.
  final DateTime Function()? now;

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

  static const statusTranslations = <String, List<String>>{
    'en': ['Sandbox access', 'Trial access confirmed until {date}', 'Paid access confirmed until {date}', 'No current trial or paid access', 'Access could not be verified'],
    'pl': ['Dostęp Sandbox', 'Dostęp próbny potwierdzony do {date}', 'Płatny dostęp potwierdzony do {date}', 'Brak aktywnego okresu próbnego lub płatnego dostępu', 'Nie udało się zweryfikować dostępu'],
    'de': ['Sandbox-Zugriff', 'Testzugriff bis {date} bestätigt', 'Bezahlter Zugriff bis {date} bestätigt', 'Kein aktueller Test- oder bezahlter Zugriff', 'Der Zugriff konnte nicht überprüft werden'],
    'sk': ['Prístup Sandbox', 'Skúšobný prístup potvrdený do {date}', 'Platený prístup potvrdený do {date}', 'Žiadny aktuálny skúšobný ani platený prístup', 'Prístup sa nepodarilo overiť'],
    'cs': ['Přístup Sandbox', 'Zkušební přístup potvrzen do {date}', 'Placený přístup potvrzen do {date}', 'Žádný aktuální zkušební ani placený přístup', 'Přístup se nepodařilo ověřit'],
    'hu': ['Sandbox-hozzáférés', 'Próba-hozzáférés megerősítve eddig: {date}', 'Fizetős hozzáférés megerősítve eddig: {date}', 'Nincs aktív próba- vagy fizetős hozzáférés', 'A hozzáférés nem ellenőrizhető'],
    'ro': ['Acces Sandbox', 'Acces de probă confirmat până la {date}', 'Acces plătit confirmat până la {date}', 'Nu există acces de probă sau plătit activ', 'Accesul nu a putut fi verificat'],
    'es': ['Acceso Sandbox', 'Acceso de prueba confirmado hasta {date}', 'Acceso de pago confirmado hasta {date}', 'No hay acceso de prueba ni de pago vigente', 'No se pudo verificar el acceso'],
    'fr': ['Accès Sandbox', 'Accès d’essai confirmé jusqu’au {date}', 'Accès payant confirmé jusqu’au {date}', 'Aucun accès d’essai ou payant en cours', 'L’accès n’a pas pu être vérifié'],
    'it': ['Accesso Sandbox', 'Accesso di prova confermato fino al {date}', 'Accesso a pagamento confermato fino al {date}', 'Nessun accesso di prova o a pagamento attivo', 'Impossibile verificare l’accesso'],
    'uk': ['Доступ Sandbox', 'Пробний доступ підтверджено до {date}', 'Платний доступ підтверджено до {date}', 'Немає активного пробного або платного доступу', 'Не вдалося перевірити доступ'],
    'pt': ['Acesso Sandbox', 'Acesso de avaliação confirmado até {date}', 'Acesso pago confirmado até {date}', 'Sem acesso de avaliação ou pago atual', 'Não foi possível verificar o acesso'],
  };

  static String text(int index) {
    final language = AppLocale.language.value;
    if (index < 6) {
      return (translations[language] ?? translations['en']!)[index];
    }
    return (statusTranslations[language] ?? statusTranslations['en']!)[index - 6];
  }

  @override
  State<GarageBillingScreen> createState() => _GarageBillingScreenState();
}

class _GarageBillingScreenState extends State<GarageBillingScreen> {
  Future<GarageEntitlementRead>? _entitlement;
  Timer? _expiryTimer;
  int _readGeneration = 0;

  DateTime _now() => (widget.now?.call() ?? DateTime.now()).toUtc();

  // Browser timers cannot reliably accept multi-month/year delays; schedule
  // only bounded checkpoints and recheck the actual UTC clock at each tick.
  // Expiry invalidates the current label without any new billing request.
  void _scheduleExpiry(DateTime until, int generation) {
    if (!mounted || generation != _readGeneration) return;
    final remaining = until.difference(_now());
    if (remaining <= Duration.zero) {
      setState(() {});
      return;
    }
    const maxDelay = Duration(days: 1);
    final delay = remaining > maxDelay ? maxDelay : remaining;
    _expiryTimer = Timer(delay, () {
      if (mounted && generation == _readGeneration) {
        _scheduleExpiry(until, generation);
      }
    });
  }

  // Refresh this widget when the server-confirmed expiry is reached, even if
  // the owner leaves this page open. Never re-query or activate billing.
  Future<void> _refreshAtExpiry(
      Future<GarageEntitlementRead> pending, int generation) async {
    try {
      final read = await pending;
      if (!mounted || generation != _readGeneration) return;
      final until = read.entitlement?.accessEndsAt;
      if (until == null || !read.allowsPaidFeaturesAt(_now())) return;
      _scheduleExpiry(until, generation);
    } catch (_) {
      // The FutureBuilder handles failed reads as an unavailable status.
    }
  }

  @override
  void initState() {
    super.initState();
    _readForCurrentWorkshop();
  }

  // Flutter may reuse this State when the user changes the active workshop.
  // Never retain a verified entitlement from the previous workspace or owner.
  void _readForCurrentWorkshop() {
    _expiryTimer?.cancel();
    final generation = ++_readGeneration;
    _entitlement = widget.isOwner && widget.loadEntitlement != null
        ? widget.loadEntitlement!()
        : null;
    final pending = _entitlement;
    if (pending != null) unawaited(_refreshAtExpiry(pending, generation));
  }

  @override
  void dispose() {
    ++_readGeneration;
    _expiryTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant GarageBillingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.workspaceId != oldWidget.workspaceId ||
        widget.workshopName != oldWidget.workshopName ||
        widget.isOwner != oldWidget.isOwner ||
        widget.loadEntitlement != oldWidget.loadEntitlement) {
      _readForCurrentWorkshop();
    }
  }

  static String _date(DateTime value) {
    String two(int value) => value.toString().padLeft(2, '0');
    final utc = value.toUtc();
    return '${utc.year}-${two(utc.month)}-${two(utc.day)} '
        '${two(utc.hour)}:${two(utc.minute)} UTC';
  }

  Widget _accessCard(BuildContext context) => FutureBuilder<GarageEntitlementRead>(
    future: _entitlement,
    builder: (context, snapshot) {
      Widget status;
      if (snapshot.connectionState == ConnectionState.waiting) {
        status = const Center(child: CircularProgressIndicator());
      } else if (!snapshot.hasData) {
        status = Text(GarageBillingScreen.text(10));
      } else {
        final read = snapshot.data!;
        final entitlement = read.entitlement;
        final message = switch (read.state) {
          GarageEntitlementReadState.disabled => GarageBillingScreen.text(10),
          GarageEntitlementReadState.unavailable => GarageBillingScreen.text(10),
          GarageEntitlementReadState.verified
              when !read.allowsPaidFeaturesAt(_now()) =>
            GarageBillingScreen.text(9),
          GarageEntitlementReadState.verified
              when entitlement?.source == GarageEntitlementSource.trial =>
            GarageBillingScreen.text(7).replaceFirst(
              '{date}', _date(entitlement!.accessEndsAt!)),
          GarageEntitlementReadState.verified =>
            GarageBillingScreen.text(8).replaceFirst(
              '{date}', _date(entitlement!.accessEndsAt!)),
        };
        status = Text(message);
      }
      return Card(child: Padding(padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(GarageBillingScreen.text(6),
            style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12), status,
        ])));
    },
  );

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String>(
    valueListenable: AppLocale.language,
    builder: (context, _, child) => Scaffold(
      appBar: AppBar(title: Text(GarageBillingScreen.text(0))),
      body: !widget.isOwner ? Center(child: Padding(
        padding: const EdgeInsets.all(24), child: Text(GarageBillingScreen.text(1)))) :
        ListView(padding: const EdgeInsets.all(16), children: [
          Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(widget.workshopName, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              if (_entitlement != null) ...[
                _accessCard(context),
                const SizedBox(height: 12),
              ],
              Card(child: Padding(padding: const EdgeInsets.all(20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.credit_card_off_outlined),
                  const SizedBox(height: 12),
                  Text(GarageBillingScreen.text(2), style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12), Text(GarageBillingScreen.text(3)),
                ]))),
              const SizedBox(height: 12),
              Card(child: Padding(padding: const EdgeInsets.all(20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(GarageBillingScreen.text(4), style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12), Text(GarageBillingScreen.text(5)),
                ]))),
            ]))),
        ]),
    ),
  );
}
