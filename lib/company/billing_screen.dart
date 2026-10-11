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

  bool get _polish => AppLocale.language.value == 'pl';
  String _t(String english, String polish) => _polish ? polish : english;

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
    if (currency == null) {
      return _BillingData(
        currency: null,
        vehicleCount: entitlements.vehicleCount,
        status: entitlements.subscriptionStatus,
        prices: const [],
      );
    }
    final rows = await client
        .from('flotaryx_billing_prices')
        .select(
          'plan_code,billing_interval,included_vehicles,max_vehicles,'
          'base_amount_minor,extra_vehicle_amount_minor',
        )
        .eq('stripe_mode', 'test')
        .eq('currency', currency)
        .eq('is_current', true);
    return _BillingData(
      currency: currency,
      vehicleCount: entitlements.vehicleCount,
      status: entitlements.subscriptionStatus,
      prices: (rows as List)
          .map(
            (item) =>
                _BillingPrice.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(),
    );
  }

  String _money(int amountMinor, String currency) {
    final formatted = (amountMinor / 100).toStringAsFixed(2);
    return switch (currency) {
      'gbp' => '£$formatted',
      'eur' => '€$formatted',
      _ => '$formatted zł',
    };
  }

  Future<void> _startCheckout(_BillingPrice price, int vehicles) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'flotaryx-create-checkout',
        body: {
          'company_id': widget.company.companyId,
          'plan_code': price.plan,
          'billing_interval': price.interval,
          'vehicle_count': vehicles,
        },
      );
      final payload = response.data;
      if (payload is! Map || payload['url'] is! String) {
        throw StateError(
          _t('Cannot prepare payment', 'Nie można przygotować płatności'),
        );
      }
      final uri = Uri.tryParse(payload['url'] as String);
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host != 'checkout.stripe.com') {
        throw StateError('Invalid Stripe checkout URL');
      }
      if (!await launchUrl(
        uri,
        mode: LaunchMode.platformDefault,
        webOnlyWindowName: '_self',
      )) {
        throw StateError(
          _t('Cannot open checkout', 'Nie można otworzyć płatności'),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_t('Subscriptions', 'Abonamenty Flotaryx'))),
      body: FutureBuilder<_BillingData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  snapshot.error.toString(),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!;
          if (data.currency == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _t(
                    'Billing is not available for this company country yet.',
                    'Płatności nie są jeszcze dostępne dla kraju tej firmy.',
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          _BillingPrice? price;
          for (final candidate in data.prices) {
            if (candidate.plan == _plan && candidate.interval == _interval) {
              price = candidate;
              break;
            }
          }
          final selected = price;
          final minimum = math.max(1, data.vehicleCount);
          final vehicles = selected == null
              ? minimum
              : (_quantity ?? math.max(minimum, selected.included));
          final valid =
              selected != null &&
              vehicles >= minimum &&
              vehicles <= selected.maximum;
          final amount = selected == null
              ? 0
              : selected.base +
                    math.max(0, vehicles - selected.included) * selected.extra;
          final alreadySubscribed = !{
            'trialing',
            'canceled',
            'unpaid',
            'incomplete',
            'paused',
          }.contains(data.status);

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
                          'SANDBOX — NO REAL CHARGES',
                          'SANDBOX — BEZ PRAWDZIWYCH OPŁAT',
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
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                _t('Select a plan', 'Wybierz plan'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: ['starter', 'pro', 'business']
                    .map(
                      (value) => ChoiceChip(
                        label: Text(
                          value[0].toUpperCase() + value.substring(1),
                        ),
                        selected: _plan == value,
                        onSelected: (_) => setState(() {
                          _plan = value;
                          _quantity = null;
                        }),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 20),
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
                onSelectionChanged: (newValues) =>
                    setState(() => _interval = newValues.first),
              ),
              if (selected != null) ...[
                const SizedBox(height: 18),
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
                            '${_t('Additional vehicle:', 'Dodatkowy pojazd:')} '
                            '${_money(selected.extra, data.currency!)}',
                          ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _t('Billable vehicles', 'Liczba pojazdów'),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: vehicles <= minimum
                                  ? null
                                  : () => setState(
                                      () => _quantity = vehicles - 1,
                                    ),
                            ),
                            Text('$vehicles'),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline),
                              onPressed: vehicles >= selected.maximum
                                  ? null
                                  : () => setState(
                                      () => _quantity = vehicles + 1,
                                    ),
                            ),
                          ],
                        ),
                        if (!valid)
                          Text(
                            _t(
                              'This plan does not cover your active fleet.',
                              'Ten plan nie obejmuje liczby pojazdów we flocie.',
                            ),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        const SizedBox(height: 12),
                        Text(
                          _money(amount, data.currency!),
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        Text(
                          _interval == 'month'
                              ? _t(
                                  'per month, excluding VAT',
                                  'miesięcznie, bez VAT',
                                )
                              : _t(
                                  'per year, excluding VAT',
                                  'rocznie, bez VAT',
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                if (alreadySubscribed)
                  Text(
                    _t(
                      'An existing subscription must be managed separately.',
                      'Istniejącym abonamentem zarządza się osobno.',
                    ),
                  )
                else
                  FilledButton.icon(
                    onPressed: !valid || _busy
                        ? null
                        : () => _startCheckout(selected, vehicles),
                    icon: const Icon(Icons.credit_card),
                    label: Text(
                      _busy
                          ? _t('Preparing...', 'Przygotowanie...')
                          : _t('Open test checkout', 'Otwórz płatność testową'),
                    ),
                  ),
              ],
              const SizedBox(height: 16),
              Text(
                _t(
                  'Test environment only. GPS is not included.',
                  'Tylko środowisko testowe. GPS nie jest wliczony.',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _BillingData {
  const _BillingData({
    required this.currency,
    required this.vehicleCount,
    required this.status,
    required this.prices,
  });
  final String? currency;
  final int vehicleCount;
  final String status;
  final List<_BillingPrice> prices;
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
