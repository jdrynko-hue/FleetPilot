import 'work_order_domain.dart';

/// Deterministic estimate comparison for a single Fleet repair request.
///
/// Inputs come from the actual workshop quote and user-entered disruption
/// assumptions. This is not a guarantee of repair timing or financial loss.
/// A comparison is never ranked if crucial data is missing or scopes differ.
enum RepairComparisonBlocker {
  tooFewOffers,
  differentRequests,
  differentRepairScopes,
  differentCurrencies,
  duplicateGarage,
  missingDowntimeCost,
  missingWorkshopEta,
  missingTransferCost,
}

class RepairCostScenario {
  RepairCostScenario({
    required this.fleetRequestId,
    required this.repairScopeKey,
    required this.quote,
    required this.daysOffRoad,
    required this.transferCostMinor,
  }) {
    if (fleetRequestId.trim().isEmpty || repairScopeKey.trim().isEmpty) {
      throw ArgumentError('Fleet repair request and repair scope are required');
    }
    if (daysOffRoad != null && daysOffRoad! < 0) {
      throw RangeError.value(daysOffRoad!, 'daysOffRoad', 'Cannot be negative');
    }
    if (transferCostMinor != null && transferCostMinor! < 0) {
      throw RangeError.value(
        transferCostMinor!,
        'transferCostMinor',
        'Cannot be negative',
      );
    }
  }

  final String fleetRequestId;
  /// Comparing unlike repair scopes would produce misleading price rankings.
  final String repairScopeKey;
  final GarageQuoteRevision quote;
  /// A workshop supplied estimate (days), never an invented availability ETA.
  final int? daysOffRoad;
  /// Delivery, collection or other transport cost, when confirmed by user.
  final int? transferCostMinor;

  String get garageWorkspaceId => quote.workspaceId;

  int? estimateTotalMinor(int? dailyDowntimeCostMinor) {
    if (dailyDowntimeCostMinor == null ||
        daysOffRoad == null ||
        transferCostMinor == null) {
      return null;
    }
    if (dailyDowntimeCostMinor < 0) {
      throw RangeError.value(
        dailyDowntimeCostMinor,
        'dailyDowntimeCostMinor',
        'Cannot be negative',
      );
    }
    return quote.totalMinor +
        daysOffRoad! * dailyDowntimeCostMinor +
        transferCostMinor!;
  }
}

class RepairCostResult {
  const RepairCostResult({required this.scenario, required this.totalMinor});

  final RepairCostScenario scenario;
  /// Estimate only; real costs and delays can change.
  final int? totalMinor;
}

class GarageRepairComparison {
  GarageRepairComparison._({
    required this.results,
    required this.blockers,
  });

  final List<RepairCostResult> results;
  final Set<RepairComparisonBlocker> blockers;

  bool get canRank => blockers.isEmpty;

  /// Sorted cheapest-first ONLY if all offers are comparable and complete.
  /// An equal cost is a tie; display it as such rather than a guaranteed winner.
  List<RepairCostResult> get ranked {
    if (!canRank) return const [];
    final ordered = List<RepairCostResult>.from(results);
    ordered.sort((a, b) {
      final cost = a.totalMinor!.compareTo(b.totalMinor!);
      if (cost != 0) return cost;
      return a.scenario.garageWorkspaceId.compareTo(
        b.scenario.garageWorkspaceId,
      );
    });
    return List.unmodifiable(ordered);
  }

  static GarageRepairComparison evaluate({
    required List<RepairCostScenario> scenarios,
    required int? dailyDowntimeCostMinor,
  }) {
    if (dailyDowntimeCostMinor != null && dailyDowntimeCostMinor < 0) {
      throw RangeError.value(
        dailyDowntimeCostMinor,
        'dailyDowntimeCostMinor',
        'Cannot be negative',
      );
    }
    final blockers = <RepairComparisonBlocker>{};
    if (scenarios.length < 2) {
      blockers.add(RepairComparisonBlocker.tooFewOffers);
    }

    if (scenarios.isNotEmpty) {
      final first = scenarios.first;
      if (scenarios.any((s) => s.fleetRequestId != first.fleetRequestId)) {
        blockers.add(RepairComparisonBlocker.differentRequests);
      }
      if (scenarios.any((s) => s.repairScopeKey != first.repairScopeKey)) {
        blockers.add(RepairComparisonBlocker.differentRepairScopes);
      }
      if (scenarios.any((s) => s.quote.currency != first.quote.currency)) {
        blockers.add(RepairComparisonBlocker.differentCurrencies);
      }
      if (scenarios.map((s) => s.garageWorkspaceId).toSet().length !=
          scenarios.length) {
        blockers.add(RepairComparisonBlocker.duplicateGarage);
      }
    }

    if (dailyDowntimeCostMinor == null) {
      blockers.add(RepairComparisonBlocker.missingDowntimeCost);
    }
    if (scenarios.any((s) => s.daysOffRoad == null)) {
      blockers.add(RepairComparisonBlocker.missingWorkshopEta);
    }
    if (scenarios.any((s) => s.transferCostMinor == null)) {
      blockers.add(RepairComparisonBlocker.missingTransferCost);
    }

    return GarageRepairComparison._(
      results: List.unmodifiable(
        scenarios.map(
          (scenario) => RepairCostResult(
            scenario: scenario,
            totalMinor: scenario.estimateTotalMinor(dailyDowntimeCostMinor),
          ),
        ),
      ),
      blockers: Set.unmodifiable(blockers),
    );
  }
}
