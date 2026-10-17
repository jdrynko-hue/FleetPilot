import 'package:flutter/material.dart';
import '../core/localization.dart';
import 'garage_ui_text.dart';

/// Navigation guidance only: never infers setup completion or publishes a shop.
class GarageSetupGuide extends StatelessWidget {
  const GarageSetupGuide({required this.openProfile, required this.openCalendar,
    required this.openRequests, super.key});
  final VoidCallback openProfile;
  final VoidCallback openCalendar;
  final VoidCallback openRequests;

  static const copy = <String, List<String>>{
    'en': ['Set up your workshop', 'Add your city and services, set opening hours and bays, then review customer requests. Publish your profile only when you are ready.'],
    'pl': ['Pierwsze kroki w warsztacie', 'Dodaj miasto i usługi, ustaw godziny otwarcia i stanowiska, a następnie obsługuj zgłoszenia klientów. Opublikuj profil dopiero wtedy, gdy będziesz gotowy.'],
    'de': ['Werkstatt einrichten', 'Fügen Sie Stadt und Leistungen hinzu, legen Sie Öffnungszeiten und Arbeitsplätze fest und bearbeiten Sie Kundenanfragen. Veröffentlichen Sie Ihr Profil erst, wenn Sie bereit sind.'],
    'sk': ['Nastavte si dielňu', 'Pridajte mesto a služby, nastavte otváracie hodiny a pracoviská a potom vybavujte požiadavky zákazníkov. Profil zverejnite, až keď budete pripravení.'],
    'cs': ['Nastavte si dílnu', 'Přidejte město a služby, nastavte otevírací dobu a pracoviště a poté vyřizujte požadavky zákazníků. Profil zveřejněte, až budete připraveni.'],
    'hu': ['Műhely beállítása', 'Adja meg a várost és a szolgáltatásokat, állítsa be a nyitvatartást és a munkaállásokat, majd kezelje az ügyfélkérelmeket. Csak akkor tegye közzé a profilt, ha készen áll.'],
    'ro': ['Configurează atelierul', 'Adaugă orașul și serviciile, stabilește programul și posturile de lucru, apoi gestionează cererile clienților. Publică profilul doar când ești pregătit.'],
    'es': ['Configura tu taller', 'Añade tu ciudad y servicios, establece horarios y puestos de trabajo y después gestiona las solicitudes de los clientes. Publica tu perfil solo cuando estés listo.'],
    'fr': ['Configurez votre atelier', 'Ajoutez votre ville et vos services, définissez les horaires et les postes de travail, puis gérez les demandes des clients. Publiez votre profil uniquement lorsque vous êtes prêt.'],
    'it': ['Configura la tua officina', 'Aggiungi città e servizi, imposta orari e postazioni di lavoro, poi gestisci le richieste dei clienti. Pubblica il profilo solo quando sei pronto.'],
    'uk': ['Налаштуйте майстерню', 'Додайте місто й послуги, налаштуйте години роботи та робочі місця, потім опрацьовуйте запити клієнтів. Публікуйте профіль лише коли будете готові.'],
    'pt': ['Configure a sua oficina', 'Adicione a cidade e os serviços, defina horários e postos de trabalho e depois gira os pedidos dos clientes. Publique o perfil apenas quando estiver pronto.'],
  };

  @override
  Widget build(BuildContext context) {
    final text = copy[AppLocale.language.value] ?? copy['en']!;
    return Card(key: const Key('garage_setup_guide'), child: Padding(
      padding: const EdgeInsets.all(16), child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(text[0], style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(text[1]),
          for (final step in <(String, VoidCallback)>[
            ('bookingProfile', openProfile),
            ('calendarSettings', openCalendar),
            ('customerRequests', openRequests),
          ].indexed)
            ListTile(key: Key('garage_setup_${step.$2.$1}'),
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(child: Text('${step.$1 + 1}')),
              title: Text(GarageUiText.get(step.$2.$1)),
              trailing: const Icon(Icons.chevron_right), onTap: step.$2.$2),
        ])));
  }
}
