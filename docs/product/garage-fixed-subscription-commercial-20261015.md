# Flotaryx Garage: abonament stały (bez prowizji) — propozycja komercyjna
**Data analizy:** 15.10.2026. **Status:** DRAFT / propozycja, NIE opublikowany cennik.
**Sprzedawca:** UK Flotaryx (podmiot i rejestracja podatkowa do potwierdzenia).
**Produkt:** B2B SaaS per warsztat / fizyczna lokalizacja; wyszukiwanie i prośba o wizytę bez opłaty Flotaryx dla prywatnego klienta.
**Nie zmienia:** istniejących cenników Fleet, Stripe Live/Test, bazy QA/PROD ani statusu publicznej rezerwacji.

## 1. Porównanie konkurencji — sprawdzone strony producentów (październik 2026)
- UK: [Motion Bookings](https://motionbookings.co.uk/pricing): £39 / £89 / £149 miesięcznie per lokalizacja, bez opłaty za użytkownika; zależnie od pakietu i funkcji.
- UK: [Garage Hive](https://garagehive.co.uk/pricing/): od £145/mies.; koszty integracji i licencji sprawdzać oddzielnie.
- UK: [Garage Shift](https://garageshift.co.uk/garage-management-software-uk): deklaruje £50/mies.; standardowo systemy niskokosztowe od ~£30.
- PL: [Warsztatnik](https://warsztatnik.pl/): 49 zł i 99 zł netto/mies. (niewielkie warsztaty, różne limity pracowników).
- PL: [Take Car](https://www.takecar.io/): 149 / 249 / 499 zł netto/mies., zależnie od wielkości zespołu/funkcji.
- UE: [Monitoro](https://monitoro.net/): €49 miesięcznie/warsztat.
- UE: [EaziGarage](https://www.eazigarage.com/en/): €10 / €40 / €100 miesięcznie, różne limity kont i faktur.
Te ceny nie oznaczają identycznego zestawu funkcji ani cen netto w każdym kraju. Nie zakładać, że Flotaryx ma obecnie gotowe wszystkie porównywane funkcje (KSeF, MOT, części, fakturowanie, SMS, live slots itp.).

## 2. Zalecany cennik pilotażowy — *osobne ceny rynkowe*, nie dynamiczne przewalutowanie
Ceny **bazowe netto / bez zastosowanego VAT**; podatki zależą od statusu prawnego, kraju i klienta.
Miesięczna opłata liczona za **jedną fizyczną lokalizację warsztatu**, a nie za mechanika, liczbę rezerwacji, zlecenie ani kwotę naprawy.

| Taryfa | UK / mies. | UE / mies. | Polska / mies. | UK / rok | UE / rok | PL / rok |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Starter | £39 | €45 | 99 zł | £390 | €450 | 990 zł |
| Team | £79 | €89 | 219 zł | £790 | €890 | 2190 zł |
| Pro | £139 | €159 | 399 zł | £1390 | €1590 | 3990 zł |

Roczny = 10 miesięcy w cenie 12 (=16,7% zniżki), zapłata za rok z góry — jasno nazwać, **nie jako comiesięczne raty**.
Dla wielu lokalizacji: osobny abonament na lokalizację z późniejszą możliwością widoku grupowego (ta możliwość jeszcze do wdrożenia). Nie naliczać żadnej prowizji od wysłanego, potwierdzonego ani zrealizowanego zgłoszenia.

**Różnice pakietowe jako docelowa specyfikacja, a nie obecna deklaracja wdrożenia:**
- Starter (do 2 stanowisk): klienci i pojazdy, zlecenia, kalendarz, kosztorysy z zatwierdzaniem, rezerwacje-na-prośbę, standardowa historia i dostęp rolowy.
- Team (do 6 stanowisk): Starter + przydziały mechaników, zaawansowane planowanie, udostępnione zgłoszenia i wyceny dla Fleet, raporty i szablony (funkcje wymagają bramkowania i testów).
- Pro (do 12 stanowisk): Team + widoki menedżerskie, eksporty/zaawansowane raporty, priorytet wsparcia po operacyjnym uruchomieniu. Nie obiecywać integracji, których nie ma.
- Ponad 12 stanowisk / wiele lokalizacji: oferta indywidualna bez domyślnego naliczania.
- Nie ograniczać podstawowego wyszukiwania i liczby próśb o termin dla warsztatu tylko z powodu pakietu; nie traktować marketplace jako usługi dodatkowo prowizyjnej.
- Dopiero po sprawdzeniu gotowości można dodać trial (np. 14 dni bez karty). Nie publikować „trial działa”, dopóki nie zostanie uruchomiony.

**Dlaczego takie ceny:** £39/£79/£139 i €45/€89/€159 mieszczą się pomiędzy budżetowym a zaawansowanym oprogramowaniem. 99/219/399 zł uwzględnia niższe lokalne ceny PL i nie jest sztywnym przeliczeniem GBP/EUR. Proponowane ceny mogą wymagać obniżenia, jeśli na premierę nie będzie istotnych funkcji wykraczających poza tanie pakiety konkurentów.

## 3. Rzeczywista ekonomika UK / Stripe dla firmy z kontem UK

Źródła pierwotne:
- [Stripe UK Payments](https://stripe.com/gb/pricing): 1,5% + £0.20 karta standardowa UK, 2,5% + £0.20 EOG, +2% przy wymaganej konwersji walut (szczegóły zależne od typu karty i płatności).
- [Stripe Billing](https://stripe.com/gb/billing/pricing): standardowo 0,7% wartości rozliczanej w Billing, dodatkowo do opłat Payments.
- [Stripe Tax](https://stripe.com/gb/tax/pricing): opcjonalnie 0,5% kwoty transakcji z obliczanym podatkiem dla integracji Billing/Checkout; zależy od zakresu aktywacji i rejestracji.
- Odczyt konta **Stripe Sandbox** Flotaryx: 3 istniejące produkty i 18 cen dotyczą **Fleet** (Starter/Pro/Business). **Nie ma produktów Garage**; planowanie osobnego katalogu, nigdy nie mapować Garage na Fleet.

Przykład **Team UK £79 bez naliczonego VAT**, standardowa karta UK, model PAYG:
- Payments = 79 × 1,5% + £0,20 = **£1,385** (~£1,39).
- Billing = 79 × 0,7% = **£0,553** (~£0,55).
- Suma modelowa Payments+Billing = **£1,938** (~£1,94), bez Stripe Tax, FX, sporów, zwrotów, fakturowania spoza planu, hostingu i supportu.
- Jeśli płatność kwalifikuje się dodatkowo do Stripe Tax 0,5%: +£0,395 (~£0,40), razem **~£2,33** przed innymi kosztami. To *ilustracja*, nie rzeczywisty koszt z faktury Stripe.
- Przy 100 aktywnych Team UK: MRR £7,900 **przed podatkiem, kosztami i zwrotami**. Modelowe Payments+Billing ~£194/mies. (bez powyższych dodatków).

UWAGA: publiczne stawki Stripe **dla kont PL / UE** (np. 1,5% + 1 zł / €0,25) nie obowiązują automatycznie konta UK Flotaryx. Dla płatności z krajów UE na brytyjskim koncie uwzględnić karty międzynarodowe, opłaty za settlement i FX w danej konfiguracji konta. Wyceny i ceny w lokalnych walutach nie gwarantują rozliczenia bez przewalutowania.

## 4. VAT i rozliczenia B2B — bramka prawno-księgowa
- Weryfikacja *rzeczywistego* statusu VAT sprzedawcy w UK, podmiotu wystawiającego faktury i sposobu raportowania (Flat Rate Scheme nie zwalnia z poprawnego określenia miejsca świadczenia).
- Sprzedaż usług UK→UK: jeśli sprzedawca jest zarejestrowany jako VAT payer, typowo VAT UK dla opodatkowanego SaaS; nie nazywać dowolnej kwoty z góry „z VAT”.
- UK→EU B2B: przy spełnionej generalnej regule miejsca świadczenia, zwykle poza zakresem UK VAT, a nabywca rozlicza odpowiedni reverse charge. Sprawdzić status kontrahenta i prawidłowy napis na fakturze / local-country rules. [HMRC](https://www.gov.uk/hmrc-internal-manuals/vat-place-of-supply-services/vatposs06300) i [notice 741A](https://www.gov.uk/guidance/vat-place-of-supply-of-services-notice-741a).
- Dla PL faktura od sprzedawcy UK nie staje się automatycznie dokumentem KSeF. Zweryfikować księgowość PL i obowiązki e-fakturowania obu stron, nie obiecywać natywnej integracji KSeF.
- B2C: sama bezpłatna prośba o wizytę nie jest opłatą za cyfrową usługę; jeśli w przyszłości Flotaryx zacznie sprzedawać płatne usługi konsumentom, analiza VAT / OSS / praw konsumenckich musi zostać wykonana ponownie.
- Checkout zbiera: kraj rejestracji firmy, billing address, VAT/tax ID, email fakturowy i walutę z serwerowo zablokowanej macierzy regionu. Weryfikacja numerów VAT, ewentualny reverse charge, domknięcie faktury — po opinii księgowej.
- PLN/EUR/GBP jako 18 odrębnych Price IDs (3 plany × 3 waluty × 2 okresy), powiązanych z **3 nowymi produktami Garage**, niewidocznych w Fleet.

## 5. Schemat płatności i ryzyka
- Stripe Checkout `mode=subscription` -> zapis serwerowy checkout session/customer/subscription id -> webhook podpisany i idempotentny; nie opierać dostępu na success_url ani na danych z przeglądarki.
- `invoice.paid` i subskrypcja są źródłem praw do płatnego modułu Garage. `invoice.payment_failed`, `customer.subscription.updated/deleted` oraz zmiany okresu powinny prowadzić przez udokumentowaną politykę grace period; nie usuwać danych warsztatu z powodu odrzuconej karty.
- Trial, jeśli wdrożony: max raz dla tożsamości/firmy wg polityki antynadużyć. Przed końcem trial wyjaśnić kwotę i datę pobrania (zwłaszcza gdy zapisywana jest karta).
- Zmiana miesięczny→roczny / planu: czytelne prorations i data kolejnego obciążenia; reset limitów tylko po podpisanym potwierdzeniu. Bez niejawnej zmiany regionu/waluty istniejącej subskrypcji.
- Zakończenie: jednoznaczny cancel-at-period-end i Customer Portal; odczyt historii/zabezpieczony eksport po anulowaniu, modyfikacje zależne od statusu. Warunki dostępu do danych, retencji, zwrotów i terminu faktury opisane w FAQ/regulaminie.
- **Brak prowizji za rezerwację** nie oznacza, że opłaty za Stripe, SMS, Google Maps, SMS czy przyszłe płatności za rzeczywistą naprawę mogą zostać ukryte pod „zero innych kosztów”. Rozdzielić koszt abonamentu Garage od opcjonalnych usług dostawców.
- Ani Flotaryx, ani Stripe nie powinny na starcie pobierać pieniędzy za usługę naprawy klientowi końcowemu przez konto Flotaryx. Warsztat rozlicza naprawę samodzielnie (chyba że później zrobimy odrębny, formalnie zatwierdzony model płatności marketplace).
- Kontrola kosztów: SMS/zdjęcia/Storage, powiadomienia, transfer, mapy, recenzje, helpdesk i akwizycja. Testy skrajnych wolumenów mimo braku opłat za zlecenie; zastosować rozsądne rate limits i politykę przechowywania.

## 6. UX na stronie (kolejny etap)
1. Główna strona: wyraźne „Dla warsztatów” + „Znajdź warsztat”, oba oznaczone „Wkrótce” do launch approval; tylko działająca Fleet ma CTA „Otwórz panel”.
2. Strona Garage: krótkie korzyści, schemat 1) rejestracja/weryfikacja 2) kalendarz/zlecenia 3) kosztorys i zgoda 4) rezerwacje 5) historia, FAQ i przełączniki kraj/waluta oraz miesiąc/rok.
3. Cena wyraźnie **za lokalizację**, bez opłaty per pracownik i **0% prowizji za rezerwacje**. Klient prywatny przegląda i prosi o termin bez prowizji Flotaryx, ale naprawa jest odpłatna u warsztatu.
4. Rozdzielić „Zaloguj” od „Utwórz warsztat”; jeśli onboarding jeszcze niedostępny, nie sugerować aktywnego przycisku zapłaty.
5. Pełne tłumaczenia 12 języków i formatu waluty z istniejącym przełącznikiem strony przed wdrożeniem na produkcję.
6. Priorytet QA: pytania o okres/plan/VAT, porównanie kwot, koszyki, limity stanowisk, dostęp po anulowaniu, różne waluty.
7. Szczegółowy szkic HTML: `design/garage-pricing-preview/index.html` — tylko lokalny podgląd w branchu, niezależny od publicznej strony.

## 7. Decyzja właściciela
**ZATWIERDZONE ZAŁOŻENIE MODELU:** stały abonament Garage, **0% prowizji od rezerwacji**.
**NIEZATWIERDZONE/DO PRZETESTOWANIA:** konkretne ceny, darmowy trial, uruchomienie subskrypcji, Stripe Live, terminy wdrożenia i opłaty opcjonalne.
