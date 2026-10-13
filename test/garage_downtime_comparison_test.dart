import 'package:flutter_test/flutter_test.dart';

import 'package:fleetpilot/garage/downtime_comparison.dart';
import 'package:fleetpilot/garage/work_order_domain.dart';

void main() {
  GarageQuoteRevision quote({
    required String garage,
    required int price,
    String currency = 'GBP',
  }) =>
      GarageQuoteRevision(
        workspaceId: garage,
        orderId: 'estimate-$garage',
        revision: 1,
        currency: currency,
        lines: [
          GarageQuoteLine(
            type: GarageQuoteLineType.labour,
            description: 'Repair labour and parts',
            quantity: 1,
            unitPriceMinor: price,
            taxMinor: 0,
          ),
        ],
      );

  RepairCostScenario offer({
    required String garage,
    required int price,
    int? days = 1,
    int? transfer = 0,
    String currency = 'GBP',
    String requestId = 'request-1',
    String scope = 'same-approved-repair',
  }) =>
      RepairCostScenario(
        fleetRequestId: requestId,
        repairScopeKey: scope,
        quote: quote(garage: garage, price: price, currency: currency),
        daysOffRoad: days,
        transferCostMinor: transfer,
      );

  test('more expensive workshop can be cheaper after fleet downtime', () {
    final a = offer(garage: 'A', price: 30000, days: 3);
    final b = offer(garage: 'B', price: 42000, days: 1);
    final result = GarageRepairComparison.evaluate(
      scenarios: [a, b],
      dailyDowntimeCostMinor: 12000,
    );
    expect(result.canRank, isTrue);
    expect(result.results.map((r) => r.totalMinor), [66000, 54000]);
    expect(result.ranked.first.scenario.garageWorkspaceId, 'B');
    expect(result.ranked.first.totalMinor, 54000);
  });

  test('no ungrounded ranking when any workshop ETA is unknown', () {
    final result = GarageRepairComparison.evaluate(
      scenarios: [
        offer(garage: 'A', price: 30000, days: 2),
        offer(garage: 'B', price: 35000, days: null),
      ],
      dailyDowntimeCostMinor: 10000,
    );
    expect(result.canRank, isFalse);
    expect(
      result.blockers,
      contains(RepairComparisonBlocker.missingWorkshopEta),
    );
    expect(result.ranked, isEmpty);
    expect(result.results.first.totalMinor, 50000);
    expect(result.results.last.totalMinor, isNull);
  });

  test('unknown daily outage cost prevents ranked recommendation', () {
    final result = GarageRepairComparison.evaluate(
      scenarios: [
        offer(garage: 'A', price: 30000),
        offer(garage: 'B', price: 32000),
      ],
      dailyDowntimeCostMinor: null,
    );
    expect(result.canRank, isFalse);
    expect(
      result.blockers,
      contains(RepairComparisonBlocker.missingDowntimeCost),
    );
    expect(result.ranked, isEmpty);
  });

  test('different currencies or repair scopes cannot be compared', () {
    final differentCurrency = GarageRepairComparison.evaluate(
      scenarios: [
        offer(garage: 'A', price: 30000, currency: 'GBP'),
        offer(garage: 'B', price: 31000, currency: 'EUR'),
      ],
      dailyDowntimeCostMinor: 1000,
    );
    expect(
      differentCurrency.blockers,
      contains(RepairComparisonBlocker.differentCurrencies),
    );
    expect(differentCurrency.canRank, isFalse);

    final differentScope = GarageRepairComparison.evaluate(
      scenarios: [
        offer(garage: 'A', price: 30000),
        offer(garage: 'B', price: 31000, scope: 'different-repair'),
      ],
      dailyDowntimeCostMinor: 1000,
    );
    expect(
      differentScope.blockers,
      contains(RepairComparisonBlocker.differentRepairScopes),
    );
    expect(differentScope.ranked, isEmpty);
  });

  test('cannot compare offers from different fleet requests', () {
    final result = GarageRepairComparison.evaluate(
      scenarios: [
        offer(garage: 'A', price: 10000),
        offer(garage: 'B', price: 10000, requestId: 'different'),
      ],
      dailyDowntimeCostMinor: 1000,
    );
    expect(
      result.blockers,
      contains(RepairComparisonBlocker.differentRequests),
    );
    expect(result.canRank, isFalse);
  });

  test('cannot treat two quotes from same garage as independent offers', () {
    final result = GarageRepairComparison.evaluate(
      scenarios: [
        offer(garage: 'A', price: 10000),
        offer(garage: 'A', price: 11000),
      ],
      dailyDowntimeCostMinor: 1000,
    );
    expect(
      result.blockers,
      contains(RepairComparisonBlocker.duplicateGarage),
    );
    expect(result.ranked, isEmpty);
  });

  test('transfer costs are included, not silently ignored', () {
    final result = GarageRepairComparison.evaluate(
      scenarios: [
        offer(garage: 'A', price: 10000, days: 1, transfer: 2000),
        offer(garage: 'B', price: 10000, days: 1, transfer: 0),
      ],
      dailyDowntimeCostMinor: 3000,
    );
    expect(result.results.first.totalMinor, 15000);
    expect(result.results.last.totalMinor, 13000);
    expect(result.ranked.first.scenario.garageWorkspaceId, 'B');
  });

  test('missing transport estimate blocks ranking instead of assuming zero',
      () {
    final result = GarageRepairComparison.evaluate(
      scenarios: [
        offer(garage: 'A', price: 10000, transfer: null),
        offer(garage: 'B', price: 12000),
      ],
      dailyDowntimeCostMinor: 1000,
    );
    expect(result.ranked, isEmpty);
    expect(
      result.blockers,
      contains(RepairComparisonBlocker.missingTransferCost),
    );
  });

  test('negative days, daily cost and transfer charge are rejected', () {
    expect(
      () => offer(garage: 'A', price: 1000, days: -1),
      throwsRangeError,
    );
    expect(
      () => offer(garage: 'A', price: 1000, transfer: -1),
      throwsRangeError,
    );
    expect(
      () => GarageRepairComparison.evaluate(
        scenarios: [
          offer(garage: 'A', price: 10000),
          offer(garage: 'B', price: 12000),
        ],
        dailyDowntimeCostMinor: -5,
      ),
      throwsRangeError,
    );
  });

  test('one quote cannot be advertised as a comparative winner', () {
    final result = GarageRepairComparison.evaluate(
      scenarios: [offer(garage: 'A', price: 1000)],
      dailyDowntimeCostMinor: 100,
    );
    expect(result.canRank, isFalse);
    expect(
      result.blockers,
      contains(RepairComparisonBlocker.tooFewOffers),
    );
    expect(result.ranked, isEmpty);
  });

  test('equal estimated totals remain ties with stable deterministic order',
      () {
    final result = GarageRepairComparison.evaluate(
      scenarios: [
        offer(garage: 'B', price: 20000, days: 1),
        offer(garage: 'A', price: 15000, days: 2),
      ],
      dailyDowntimeCostMinor: 5000,
    );
    expect(result.canRank, isTrue);
    expect(result.ranked.map((r) => r.totalMinor), [25000, 25000]);
    expect(
      result.ranked.map((r) => r.scenario.garageWorkspaceId),
      ['A', 'B'],
    );
  });

  test('results and failure reasons cannot be modified by callers', () {
    final result = GarageRepairComparison.evaluate(
      scenarios: [
        offer(garage: 'A', price: 1000),
        offer(garage: 'B', price: 2000),
      ],
      dailyDowntimeCostMinor: 100,
    );
    expect(
      () => result.results.clear(),
      throwsUnsupportedError,
    );
    expect(
      () => result.ranked.clear(),
      throwsUnsupportedError,
    );
    expect(
      () => result.blockers.add(RepairComparisonBlocker.tooFewOffers),
      throwsUnsupportedError,
    );
  });
}
