/// Pure Garage work-order rules. No network access, storage or privileged RPCs.
///
/// These validations improve UI correctness. They are NOT authorization
/// enforcement: the eventual Garage backend must independently enforce
/// workspace isolation, approved quote revisions and actor permissions via RLS
/// and secure server-side functions.
enum GarageOrderStatus {
  received,
  diagnosing,
  awaitingApproval,
  awaitingParts,
  inProgress,
  ready,
  collected,
  cancelled,
}

enum GarageTeamRole { owner, serviceAdvisor, mechanic }

enum GarageQuoteLineType { labour, part, other }

/// Who approved the estimate (identity/proof verified by backend, not by UI).
enum GarageQuoteApprovalKind { customer, fleetManager }

const _statusTransitions = <GarageOrderStatus, Set<GarageOrderStatus>>{
  GarageOrderStatus.received: {
    GarageOrderStatus.diagnosing,
    GarageOrderStatus.cancelled,
  },
  GarageOrderStatus.diagnosing: {
    GarageOrderStatus.awaitingApproval,
    GarageOrderStatus.cancelled,
  },
  GarageOrderStatus.awaitingApproval: {
    GarageOrderStatus.diagnosing,
    GarageOrderStatus.awaitingParts,
    GarageOrderStatus.inProgress,
    GarageOrderStatus.cancelled,
  },
  GarageOrderStatus.awaitingParts: {
    GarageOrderStatus.inProgress,
    GarageOrderStatus.cancelled,
  },
  GarageOrderStatus.inProgress: {
    GarageOrderStatus.awaitingParts,
    GarageOrderStatus.ready,
    GarageOrderStatus.cancelled,
  },
  GarageOrderStatus.ready: {GarageOrderStatus.collected},
  GarageOrderStatus.collected: {},
  GarageOrderStatus.cancelled: {},
};

class GarageQuoteLine {
  GarageQuoteLine({
    required this.type,
    required this.description,
    required this.quantity,
    required this.unitPriceMinor,
    required this.taxMinor,
  }) {
    if (description.trim().isEmpty) {
      throw ArgumentError.value(description, 'description', 'Required');
    }
    if (quantity < 1 || quantity > 10000) {
      throw RangeError.range(quantity, 1, 10000, 'quantity');
    }
    if (unitPriceMinor < 0 || taxMinor < 0) {
      throw ArgumentError('Price and line tax must not be negative');
    }
  }

  final GarageQuoteLineType type;
  final String description;
  final int quantity;
  /// Integer minor currency units: pence, cents or grosz.
  final int unitPriceMinor;
  /// Total tax for the complete line, also in integer minor units.
  final int taxMinor;

  int get subtotalMinor => quantity * unitPriceMinor;
  int get totalMinor => subtotalMinor + taxMinor;
}

class GarageQuoteRevision {
  GarageQuoteRevision({
    required this.workspaceId,
    required this.orderId,
    required this.revision,
    required this.currency,
    required List<GarageQuoteLine> lines,
  }) : lines = List.unmodifiable(lines) {
    if (workspaceId.trim().isEmpty || orderId.trim().isEmpty) {
      throw ArgumentError('Workspace and order IDs are required');
    }
    if (revision < 1) {
      throw RangeError.value(revision, 'revision', 'Must be at least 1');
    }
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(currency)) {
      throw ArgumentError.value(currency, 'currency', 'Expected ISO code');
    }
    if (this.lines.isEmpty) {
      throw ArgumentError('At least one estimate line is required');
    }
  }

  final String workspaceId;
  final String orderId;
  final int revision;
  final String currency;
  final List<GarageQuoteLine> lines;

  int get subtotalMinor =>
      lines.fold(0, (total, line) => total + line.subtotalMinor);
  int get taxMinor => lines.fold(0, (total, line) => total + line.taxMinor);
  int get totalMinor => subtotalMinor + taxMinor;
}

class GarageWorkOrder {
  const GarageWorkOrder({
    required this.workspaceId,
    required this.id,
    this.status = GarageOrderStatus.received,
    this.quote,
    this.approvedRevision,
    this.approvalKind,
  });

  final String workspaceId;
  final String id;
  final GarageOrderStatus status;
  final GarageQuoteRevision? quote;
  final int? approvedRevision;
  final GarageQuoteApprovalKind? approvalKind;

  bool get hasCurrentQuoteApproval =>
      quote != null &&
      approvedRevision == quote!.revision &&
      approvalKind != null;

  /// Existing quote approval is deliberately invalidated on EVERY revision.
  GarageWorkOrder reviseQuote({
    required GarageQuoteRevision next,
    required GarageTeamRole actor,
  }) {
    if (actor == GarageTeamRole.mechanic) {
      throw StateError('Mechanics cannot publish estimates');
    }
    if (status != GarageOrderStatus.diagnosing &&
        status != GarageOrderStatus.awaitingApproval) {
      throw StateError('Estimates cannot be edited in this work-order status');
    }
    if (next.workspaceId != workspaceId || next.orderId != id) {
      throw StateError('Estimate is for another garage or work order');
    }
    if (next.revision != (quote?.revision ?? 0) + 1) {
      throw StateError('Estimate revision must increase by exactly one');
    }
    if (quote != null && next.currency != quote!.currency) {
      throw StateError('Currency cannot change between estimate revisions');
    }
    return GarageWorkOrder(
      workspaceId: workspaceId,
      id: id,
      status: status,
      quote: next,
    );
  }

  /// Caller must verify the approver's identity and approval evidence on
  /// the server. Passing an enum here does not grant approval privileges.
  GarageWorkOrder recordApprovedQuote({
    required int revision,
    required GarageQuoteApprovalKind kind,
  }) {
    if (status != GarageOrderStatus.awaitingApproval ||
        quote == null ||
        quote!.revision != revision) {
      throw StateError('Only the current pending estimate can be approved');
    }
    if (hasCurrentQuoteApproval) {
      throw StateError('The current estimate is already approved');
    }
    return GarageWorkOrder(
      workspaceId: workspaceId,
      id: id,
      status: status,
      quote: quote,
      approvedRevision: revision,
      approvalKind: kind,
    );
  }

  GarageWorkOrder moveTo(
    GarageOrderStatus next, {
    required GarageTeamRole actor,
  }) {
    if (!(_statusTransitions[status]?.contains(next) ?? false)) {
      throw StateError('Invalid work-order status change: $status → $next');
    }
    if ((next == GarageOrderStatus.cancelled ||
            next == GarageOrderStatus.collected ||
            next == GarageOrderStatus.awaitingApproval) &&
        actor == GarageTeamRole.mechanic) {
      throw StateError('A service adviser or owner must confirm this action');
    }
    if (next == GarageOrderStatus.awaitingApproval && quote == null) {
      throw StateError('An estimate must be published before approval');
    }
    if ((next == GarageOrderStatus.awaitingParts ||
            next == GarageOrderStatus.inProgress ||
            next == GarageOrderStatus.ready) &&
        !hasCurrentQuoteApproval) {
      throw StateError('The latest estimate needs approval before work starts');
    }
    return GarageWorkOrder(
      workspaceId: workspaceId,
      id: id,
      status: next,
      quote: quote,
      approvedRevision: approvedRevision,
      approvalKind: approvalKind,
    );
  }
}
