import 'dart:async';
import 'package:flutter/material.dart';
import '../core/localization.dart';
import 'entitlement_repository.dart';

/// Informational only. Every mutation remains independently server-authorized.
/// No hidden page or cached positive result grants a paid write.
class GarageOperationAccessNotice extends StatefulWidget {
  const GarageOperationAccessNotice({required this.scopeId, required this.load,
    this.now, super.key});
  final String scopeId;
  final Future<GarageEntitlementRead> Function() load;
  final DateTime Function()? now;
  @override
  State<GarageOperationAccessNotice> createState() => _NoticeState();
}

class _NoticeState extends State<GarageOperationAccessNotice>
    with WidgetsBindingObserver {
  GarageEntitlementRead? _read;
  bool _busy = true;
  int _generation = 0;
  Timer? _expiry;
  Timer? _contextCheck;
  DateTime _now() => widget.now?.call().toUtc() ?? DateTime.now().toUtc();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _contextCheck = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && !_busy) setState(() {});
    });
    _refresh();
  }
  @override
  void didUpdateWidget(covariant GarageOperationAccessNotice oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scopeId != widget.scopeId || oldWidget.load != widget.load) {
      _refresh();
    }
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }
  @override
  void dispose() {
    _generation++;
    _expiry?.cancel();
    _contextCheck?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  Future<void> _refresh() async {
    final generation = ++_generation;
    final load = widget.load;
    _expiry?.cancel();
    setState(() { _read = null; _busy = true; });
    GarageEntitlementRead read;
    try {
      read = await load().timeout(const Duration(seconds: 12));
    } catch (_) {
      read = const GarageEntitlementRead.unavailable();
    }
    if (!mounted || generation != _generation) return;
    setState(() { _read = read; _busy = false; });
    final end = read.entitlement?.accessEndsAt;
    final duration = end?.difference(_now());
    if (duration != null && duration > Duration.zero) {
      _expiry = Timer(duration, () { if (mounted) setState(() {}); });
    }
  }
  static String text(bool inactive) {
    final texts = <String, (String, String)>{
      'pl': ('Dostęp ograniczony. Historia pozostaje dostępna; można domknąć wcześniej rozpoczęte naprawy. Nowa praca i rezerwacje wymagają aktywnego abonamentu.', 'Nie potwierdzono abonamentu. Odśwież status przed nową operacją.'),
      'en': ('Limited access. History remains available and eligible repairs can be completed. New work and bookings require an active subscription.', 'Subscription not verified. Refresh the status before a new operation.'),
      'de': ('Eingeschränkter Zugriff. Verlauf und Abschluss berechtigter Reparaturen bleiben verfügbar. Neue Arbeiten und Buchungen erfordern ein aktives Abonnement.', 'Abonnement nicht bestätigt. Status vor einem neuen Vorgang aktualisieren.'),
      'sk': ('Obmedzený prístup. História a dokončenie oprávnených opráv zostávajú dostupné. Nová práca a rezervácie vyžadujú aktívne predplatné.', 'Predplatné nebolo overené. Pred novou operáciou obnovte stav.'),
      'cs': ('Omezený přístup. Historie a dokončení oprávněných oprav zůstávají dostupné. Nová práce a rezervace vyžadují aktivní předplatné.', 'Předplatné nebylo ověřeno. Před novou operací obnovte stav.'),
      'hu': ('Korlátozott hozzáférés. Az előzmények és a jogosult javítások lezárása elérhető. Új munkához és foglaláshoz aktív előfizetés kell.', 'Az előfizetés nincs ellenőrizve. Új művelet előtt frissítse az állapotot.'),
      'ro': ('Acces limitat. Istoricul și finalizarea reparațiilor eligibile rămân disponibile. Lucrările și rezervările noi necesită un abonament activ.', 'Abonamentul nu a fost verificat. Actualizați starea înainte de o operațiune nouă.'),
      'es': ('Acceso limitado. El historial y la finalización de reparaciones válidas siguen disponibles. Los nuevos trabajos y reservas requieren una suscripción activa.', 'Suscripción sin verificar. Actualiza el estado antes de una nueva operación.'),
      'fr': ('Accès limité. L’historique et la clôture des réparations admissibles restent disponibles. Les nouveaux travaux et réservations nécessitent un abonnement actif.', 'Abonnement non vérifié. Actualisez le statut avant une nouvelle opération.'),
      'it': ('Accesso limitato. Cronologia e completamento delle riparazioni idonee restano disponibili. Nuovi lavori e prenotazioni richiedono un abbonamento attivo.', 'Abbonamento non verificato. Aggiorna lo stato prima di una nuova operazione.'),
      'uk': ('Обмежений доступ. Історія та завершення відповідних ремонтів залишаються доступними. Нові роботи й бронювання потребують активної підписки.', 'Підписку не перевірено. Оновіть стан перед новою дією.'),
      'pt': ('Acesso limitado. O histórico e a conclusão de reparações elegíveis continuam disponíveis. Novos trabalhos e reservas exigem uma subscrição ativa.', 'Subscrição não verificada. Atualize o estado antes de uma nova operação.'),
      'lt': ('Ribota prieiga. Istorija ir tinkamų remontų užbaigimas lieka prieinami. Naujiems darbams ir rezervacijoms reikia aktyvios prenumeratos.', 'Prenumerata nepatikrinta. Prieš naują veiksmą atnaujinkite būseną.'),
    };
    final value = texts[AppLocale.language.value] ?? texts['en']!;
    return inactive ? value.$1 : value.$2;
  }
  @override
  Widget build(BuildContext context) {
    final read = _read;
    if (!_busy && read?.allowsPaidFeaturesAt(_now()) == true) return const SizedBox.shrink();
    final inactive = !_busy && read?.state == GarageEntitlementReadState.verified;
    return Material(color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: SafeArea(bottom: false, child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(children: [
          if (_busy) const SizedBox(width: 16, height: 16,
            child: CircularProgressIndicator(strokeWidth: 2))
          else const Icon(Icons.info_outline),
          const SizedBox(width: 10),
          Expanded(child: Text(text(inactive), key: const Key('garage_operation_notice'))),
          IconButton(key: const Key('garage_operation_refresh'),
            onPressed: _busy ? null : _refresh, icon: const Icon(Icons.refresh)),
        ]),
      )));
  }
}
