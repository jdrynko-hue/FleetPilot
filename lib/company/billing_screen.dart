import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/localization.dart';
import '../data/fleet_repository.dart';
import '../data/models.dart';

class BillingScreen extends StatefulWidget {
  const BillingScreen({required this.company, super.key});
  final CompanyMembership company;

  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen> {
  final _repository = FleetRepository();
  late Future<_BillingData> _future;
  String _plan = 'starter';
  String _interval = 'month';
  int? _quantity;
  bool _busy = false;
  bool _b2bConfirmed = false;
  String _billingMode = 'test';
  // A separate, explicit production launch is required. The existing Sandbox stays operational.
  static const bool _liveBillingAvailable = bool.fromEnvironment(
    'FLOTARYX_LIVE_BILLING',
    defaultValue: false,
  );

  bool get _polish => AppLocale.language.value == 'pl';
  String _t(String en, String pl) => _polish ? pl : en;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_BillingData> _load() async {
    final client = Supabase.instance.client;
    final company = await client
        .from('companies')
        .select('country')
        .eq('id', widget.company.companyId)
        .single();
    final country = (company['country'] as String? ?? '').toUpperCase();
    const eurozone = {
      'AT',
      'BE',
      'BG',
      'HR',
      'CY',
      'EE',
      'FI',
      'FR',
      'DE',
      'GR',
      'IE',
      'IT',
      'LV',
      'LT',
      'LU',
      'MT',
      'NL',
      'PT',
      'SK',
      'SI',
      'ES',
    };
    final currency = country == 'GB'
        ? 'gbp'
        : country == 'PL'
        ? 'pln'
        : eurozone.contains(country)
        ? 'eur'
        : null;
    final entitlements = await _repository.fetchCompanyEntitlements(
      widget.company.companyId,
    );
    final subscription = await client
        .from('company_subscriptions')
        .select(
          'plan_code,status,billing_provider,stripe_subscription_id,stripe_price_id,'
          'billing_interval,billable_vehicle_count,cancel_at_period_end,current_period_end',
        )
        .eq('company_id', widget.company.companyId)
        .single();
    final hasStripe =
        subscription['billing_provider'] == 'stripe' &&
        (subscription['stripe_subscription_id']?.toString().startsWith(
              'sub_',
            ) ??
            false);
    String effectiveMode = 'test';
    if (hasStripe) {
      final existingPriceId = subscription['stripe_price_id']?.toString();
      if (existingPriceId == null || !existingPriceId.startsWith('price_')) {
        throw StateError(
          'Cannot determine existing Stripe subscription environment',
        );
      }
      final existingPrice = await client
          .from('flotaryx_billing_prices')
          .select('stripe_mode')
          .eq('stripe_price_id', existingPriceId)
          .maybeSingle();
      final storedMode = existingPrice?['stripe_mode']?.toString();
      if (storedMode != 'test' && storedMode != 'live') {
        throw StateError(
          'Existing subscription price has an unknown Stripe environment',
        );
      }
      effectiveMode = storedMode!;
    } else if (_liveBillingAvailable) {
      effectiveMode = 'live';
    }
    _billingMode = effectiveMode;
    if (hasStripe) {
      final savedPlan = subscription['plan_code']?.toString();
      if (['starter', 'pro', 'business'].contains(savedPlan))
        _plan = savedPlan!;
      _interval = subscription['billing_interval'] == 'annual'
          ? 'year'
          : 'month';
      _quantity = (subscription['billable_vehicle_count'] as num?)?.toInt();
    }
    if (currency == null) {
      return _BillingData(
        currency: null,
        vehicleCount: entitlements.vehicleCount,
        status: entitlements.subscriptionStatus,
        prices: const [],
        hasStripe: hasStripe,
        cancellationScheduled: subscription['cancel_at_period_end'] == true,
        renewalAt: subscription['current_period_end']?.toString(),
      );
    }
    final rows = await client
        .from('flotaryx_billing_prices')
        .select(
          'plan_code,billing_interval,included_vehicles,max_vehicles,'
          'base_amount_minor,extra_vehicle_amount_minor',
        )
        .eq('stripe_mode', effectiveMode)
        .eq('currency', currency)
        .eq('is_current', true);
    return _BillingData(
      currency: currency,
      vehicleCount: entitlements.vehicleCount,
      status:
          subscription['status']?.toString() ?? entitlements.subscriptionStatus,
      prices: (rows as List)
          .map(
            (item) =>
                _BillingPrice.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(),
      hasStripe: hasStripe,
      cancellationScheduled: subscription['cancel_at_period_end'] == true,
      renewalAt: subscription['current_period_end']?.toString(),
    );
  }

  void _reload() => setState(() {
    _future = _load();
  });

  String _money(int amountMinor, String currency) {
    final formatted = (amountMinor / 100).toStringAsFixed(2);
    return switch (currency) {
      'gbp' => '£$formatted',
      'eur' => '€$formatted',
      _ => '$formatted zł',
    };
  }

  Future<Map<String, dynamic>> _manage(
    String action, [
    Map<String, dynamic>? extras,
  ]) async {
    final response = await Supabase.instance.client.functions.invoke(
      _billingMode == 'live'
          ? 'flotaryx-live-billing-manage'
          : 'flotaryx-billing-manage',
      body: {
        'company_id': widget.company.companyId,
        'action': action,
        ...?extras,
      },
    );
    if (response.data is! Map)
      throw StateError(
        _t('Invalid billing response', 'Nieprawidłowa odpowiedź rozliczeń'),
      );
    final payload = Map<String, dynamic>.from(response.data as Map);
    if (payload['error'] != null) throw StateError(payload['error'].toString());
    return payload;
  }

  Future<void> _openStripeUri(String address, {bool portal = false}) async {
    final uri = Uri.tryParse(address);
    if (uri == null ||
        uri.scheme != 'https' ||
        (portal
            ? uri.host != 'billing.stripe.com'
            : uri.host != 'checkout.stripe.com')) {
      throw StateError('Invalid Stripe URL');
    }
    if (!await launchUrl(
      uri,
      mode: LaunchMode.platformDefault,
      webOnlyWindowName: '_self',
    )) {
      throw StateError(_t('Cannot open Stripe', 'Nie można otworzyć Stripe'));
    }
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(error.toString())));
  }

  Future<void> _startCheckout(_BillingPrice price, int vehicles) async {
    if (_busy) return;
    if (!_b2bConfirmed) {
      _showError(StateError(tr('b2b_only')));
      return;
    }
    setState(() => _busy = true);
    try {
      final response = await Supabase.instance.client.functions.invoke(
        _billingMode == 'live'
            ? 'flotaryx-live-create-checkout'
            : 'flotaryx-create-checkout',
        body: {
          'company_id': widget.company.companyId,
          'plan_code': price.plan,
          'billing_interval': price.interval,
          'vehicle_count': vehicles,
          'business_purchase_confirmed': _b2bConfirmed,
        },
      );
      if (response.data is! Map || (response.data as Map)['url'] is! String) {
        throw StateError(
          _t('Cannot prepare payment', 'Nie można przygotować płatności'),
        );
      }
      await _openStripeUri((response.data as Map)['url'] as String);
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(_t('Back', 'Wróć')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(_t('Confirm', 'Potwierdź')),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _execute(
    String action, {
    Map<String, dynamic>? extras,
    String? title,
    String? warning,
  }) async {
    if (_busy) return;
    if (title != null && warning != null && !await _confirm(title, warning))
      return;
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      final result = await _manage(action, extras);
      if (action == 'portal') {
        await _openStripeUri(result['url'] as String, portal: true);
      } else {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _t('Request accepted by Stripe', 'Stripe przyjął zmianę'),
              ),
            ),
          );
        _reload();
      }
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showInvoices(String currency) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await _manage('invoices');
      final invoices = (result['invoices'] as List? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _t('Invoices and receipts', 'Faktury i rachunki'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                if (invoices.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(18),
                    child: Text(_t('No invoices yet', 'Brak faktur')),
                  ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: invoices.map((invoice) {
                      final total = (invoice['total'] as num?)?.toInt() ?? 0;
                      final invoiceCurrency =
                          invoice['currency']?.toString() ?? currency;
                      final date =
                          invoice['created']?.toString().split('T').first ?? '';
                      final url =
                          invoice['invoice_url']?.toString() ??
                          invoice['pdf_url']?.toString();
                      return ListTile(
                        title: Text(
                          '${_money(total, invoiceCurrency)} — ${invoice['status'] ?? ''}',
                        ),
                        subtitle: Text('${invoice['number'] ?? ''}  $date'),
                        trailing: Icon(
                          url != null ? Icons.open_in_new : Icons.receipt_long,
                        ),
                        onTap: url == null
                            ? null
                            : () async {
                                final uri = Uri.tryParse(url);
                                if (uri != null &&
                                    uri.scheme == 'https' &&
                                    (uri.host == 'invoice.stripe.com' ||
                                        uri.host == 'pay.stripe.com')) {
                                  await launchUrl(
                                    uri,
                                    mode: LaunchMode.platformDefault,
                                    webOnlyWindowName: '_blank',
                                  );
                                }
                              },
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_t('Subscriptions', 'Abonamenty Flotaryx')),
      actions: [
        IconButton(
          onPressed: _busy ? null : _reload,
          tooltip: _t('Refresh', 'Odśwież'),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: FutureBuilder<_BillingData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError)
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                snapshot.error.toString(),
                textAlign: TextAlign.center,
              ),
            ),
          );
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        final data = snapshot.data!;
        if (data.currency == null)
          return Center(
            child: Text(
              _t(
                'Billing is not available in your company country yet.',
                'Rozliczenia nie są dostępne w kraju tej firmy.',
              ),
            ),
          );
        _BillingPrice? selected;
        for (final candidate in data.prices) {
          if (candidate.plan == _plan && candidate.interval == _interval) {
            selected = candidate;
            break;
          }
        }
        final minimum = math.max(1, data.vehicleCount);
        final vehicles = selected == null
            ? minimum
            : (_quantity ?? math.max(minimum, selected.included));
        final valid =
            selected != null &&
            vehicles >= minimum &&
            vehicles >= selected.included &&
            vehicles <= selected.maximum;
        final amount = selected == null
            ? 0
            : selected.base +
                  math.max(0, vehicles - selected.included) * selected.extra;
        final billable = data.hasStripe;
        final active = ['active', 'trialing', 'past_due'].contains(data.status);
        // The server only permits a plan change for active/trialing subscriptions.
        final canChangePlan = ['active', 'trialing'].contains(data.status);
        // A finished Sandbox subscription can be restarted through a new Checkout.
        // The backend independently verifies cancellation with Stripe.
        final canRestart = billable &&
            data.status == 'canceled' &&
            _billingMode == 'test';
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 36),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _t(
                        _billingMode == 'live'
                            ? 'LIVE — Real payments'
                            : 'SANDBOX — NO REAL CHARGES',
                        _billingMode == 'live'
                            ? 'LIVE — Prawdziwe płatności'
                            : 'SANDBOX — BEZ PRAWDZIWYCH OPŁAT',
                      ),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.company.companyName,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      '${_t('Currency:', 'Waluta:')} ${data.currency!.toUpperCase()}',
                    ),
                    Text(
                      '${_t('Active vehicles:', 'Aktywne pojazdy:')} ${data.vehicleCount}',
                    ),
                    Text(
                      '${_t('Subscription status:', 'Status abonamentu:')} ${data.status}',
                    ),
                    if (data.cancellationScheduled)
                      Text(
                        _t(
                          'Cancellation scheduled at period end.',
                          'Anulowanie zaplanowane na koniec okresu.',
                        ),
                      ),
                    if (billable && data.renewalAt != null)
                      Text(
                        '${_t('Period ends:', 'Koniec okresu:')} ${data.renewalAt!.split('T').first}',
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (billable && data.status == 'past_due')
              Card(
                child: ListTile(
                  leading: const Icon(Icons.warning_amber_outlined),
                  title: Text(_t('Payment overdue', 'Zaległa płatność')),
                  subtitle: Text(
                    _t(
                      'Update your payment method to resolve the outstanding payment before changing plans.',
                      'Zaktualizuj metodę płatności, aby uregulować zaległość przed zmianą planu.',
                    ),
                  ),
                ),
              ),
            if (billable &&
                ['unpaid', 'incomplete', 'paused'].contains(data.status))
              Card(
                child: ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: Text(_t('Subscription inactive', 'Abonament nieaktywny')),
                  subtitle: Text(
                    _t(
                      'The current subscription cannot be changed here. Contact support if you need to restart billing.',
                      'Nie można zmienić tego abonamentu. Skontaktuj się z pomocą, aby wznowić rozliczenia.',
                    ),
                  ),
                ),
              ),
            if (canRestart)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.restart_alt),
                  title: Text(_t('Subscription ended', 'Abonament zakończony')),
                  subtitle: Text(_t(
                    'You can select a plan and restart your subscription in Stripe Sandbox.',
                    'Możesz wybrać plan i ponownie wykupić abonament w Stripe Sandbox.',
                  )),
                ),
              ),
            if (billable) ...[
              Text(
                _t('Manage subscription', 'Zarządzanie abonamentem'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _showInvoices(data.currency!),
                    icon: const Icon(Icons.receipt_long),
                    label: Text(_t('Invoices', 'Faktury')),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _execute('portal'),
                    icon: const Icon(Icons.credit_card),
                    label: Text(_t('Payment details', 'Metoda płatności')),
                  ),
                  if (active && !data.cancellationScheduled)
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _execute(
                              'cancel',
                              title: _t(
                                'Cancel renewal?',
                                'Anulować odnowienie?',
                              ),
                              warning: _t(
                                'Subscription remains active until the end of the paid period.',
                                'Abonament pozostanie aktywny do końca opłaconego okresu.',
                              ),
                            ),
                      icon: const Icon(Icons.event_busy),
                      label: Text(_t('Cancel renewal', 'Anuluj odnowienie')),
                    ),
                  if (data.cancellationScheduled && active)
                    FilledButton.tonalIcon(
                      onPressed: _busy ? null : () => _execute('resume'),
                      icon: const Icon(Icons.restart_alt),
                      label: Text(_t('Resume renewal', 'Wznów odnowienie')),
                    ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            Text(
              _t(
                billable && !canRestart ? 'Change your plan' : 'Choose a plan',
                billable && !canRestart ? 'Zmień plan' : 'Wybierz plan',
              ),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: ['starter', 'pro', 'business']
                  .map(
                    (value) => ChoiceChip(
                      label: Text(value[0].toUpperCase() + value.substring(1)),
                      selected: _plan == value,
                      onSelected: (_) => setState(() {
                        _plan = value;
                        _quantity = null;
                      }),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 16),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(
                  value: 'month',
                  label: Text(_t('Monthly', 'Miesięcznie')),
                ),
                ButtonSegment(
                  value: 'year',
                  label: Text(_t('Yearly', 'Rocznie')),
                ),
              ],
              selected: {_interval},
              onSelectionChanged: (values) => setState(() {
                _interval = values.first;
                _quantity = null;
              }),
            ),
            if (selected != null) ...[
              const SizedBox(height: 14),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_t('Included vehicles:', 'Pojazdy w cenie:')} ${selected.included}',
                      ),
                      Text(
                        '${_t('Maximum vehicles:', 'Maksymalna liczba:')} ${selected.maximum}',
                      ),
                      if (selected.extra > 0)
                        Text(
                          '${_t('Additional vehicle:', 'Dodatkowy pojazd:')} ${_money(selected.extra, data.currency!)}',
                        ),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _t('Billable vehicles', 'Liczba pojazdów'),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed:
                                vehicles <= math.max(minimum, selected.included)
                                ? null
                                : () =>
                                      setState(() => _quantity = vehicles - 1),
                          ),
                          Text('$vehicles'),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline),
                            onPressed: vehicles >= selected.maximum
                                ? null
                                : () =>
                                      setState(() => _quantity = vehicles + 1),
                          ),
                        ],
                      ),
                      if (!valid)
                        Text(
                          _t(
                            'This plan cannot cover the selected fleet size.',
                            'Ten plan nie obejmuje wybranej wielkości floty.',
                          ),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      const SizedBox(height: 8),
                      Text(
                        _money(amount, data.currency!),
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      Text(
                        _interval == 'month'
                            ? _t(
                                'per month, excluding tax',
                                'miesięcznie, bez VAT',
                              )
                            : _t('per year, excluding tax', 'rocznie, bez VAT'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (!billable || canRestart) ...[
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr('b2b_confirmation')),
                  subtitle: Text(tr('b2b_only')),
                  value: _b2bConfirmed,
                  controlAffinity: ListTileControlAffinity.leading,
                  onChanged: _busy
                      ? null
                      : (value) =>
                            setState(() => _b2bConfirmed = value ?? false),
                ),
                const SizedBox(height: 8),
              ],
              if (billable && canChangePlan && !data.cancellationScheduled)
                FilledButton.icon(
                  onPressed: (!valid || _busy)
                      ? null
                      : () => _execute(
                          'change',
                          extras: {
                            'plan_code': selected!.plan,
                            'billing_interval': selected.interval,
                            'vehicle_count': vehicles,
                          },
                          title: _t(
                            'Confirm plan change',
                            'Potwierdź zmianę planu',
                          ),
                          warning: _t(
                            'Stripe may add a proportional charge or credit to your next invoice. New price: ${_money(amount, data.currency!)} before tax.',
                            'Stripe może naliczyć proporcjonalną dopłatę lub uznanie na kolejnej fakturze. Nowa cena: ${_money(amount, data.currency!)} bez VAT.',
                          ),
                        ),
                  icon: const Icon(Icons.swap_horiz),
                  label: Text(
                    _busy
                        ? _t('Updating...', 'Aktualizacja...')
                        : _t('Change subscription', 'Zmień abonament'),
                  ),
                )
              else if (!billable || canRestart)
                FilledButton.icon(
                  onPressed:
                      (!valid ||
                          _busy ||
                          !_b2bConfirmed ||
                          (_billingMode == 'live' && !_liveBillingAvailable))
                      ? null
                      : () => _startCheckout(selected!, vehicles),
                  icon: const Icon(Icons.credit_card),
                  label: Text(
                    _busy
                        ? _t('Preparing...', 'Przygotowanie...')
                        : canRestart
                        ? _t('Restart test subscription', 'Wykup ponownie testowy abonament')
                        : _billingMode == 'live'
                        ? _t(
                            'Open secure checkout',
                            'Otwórz bezpieczną płatność',
                          )
                        : _t('Open test checkout', 'Otwórz płatność testową'),
                  ),
                ),
            ],
            const SizedBox(height: 14),
            Text(
              _t(
                _billingMode == 'live'
                    ? 'Production subscriptions. GPS not included. Taxes may apply.'
                    : 'Test environment only. GPS not included. Price changes can be prorated.',
                _billingMode == 'live'
                    ? 'Abonament produkcyjny. GPS nie jest wliczony. Mogą być naliczone podatki.'
                    : 'Tylko środowisko testowe. GPS nie jest wliczony. Zmiany ceny mogą być rozliczane proporcjonalnie.',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        );
      },
    ),
  );
}

class _BillingData {
  const _BillingData({
    required this.currency,
    required this.vehicleCount,
    required this.status,
    required this.prices,
    required this.hasStripe,
    required this.cancellationScheduled,
    required this.renewalAt,
  });
  final String? currency;
  final int vehicleCount;
  final String status;
  final List<_BillingPrice> prices;
  final bool hasStripe;
  final bool cancellationScheduled;
  final String? renewalAt;
}

class _BillingPrice {
  const _BillingPrice(
    this.plan,
    this.interval,
    this.included,
    this.maximum,
    this.base,
    this.extra,
  );
  final String plan;
  final String interval;
  final int included, maximum, base, extra;
  factory _BillingPrice.fromJson(Map<String, dynamic> row) => _BillingPrice(
    row['plan_code'] as String,
    row['billing_interval'] as String,
    (row['included_vehicles'] as num).toInt(),
    (row['max_vehicles'] as num).toInt(),
    (row['base_amount_minor'] as num).toInt(),
    (row['extra_vehicle_amount_minor'] as num).toInt(),
  );
}
