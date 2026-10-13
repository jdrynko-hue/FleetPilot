import 'package:flutter_test/flutter_test.dart';

import 'package:fleetpilot/garage/work_order_domain.dart';

void main() {
  GarageQuoteRevision quote({
    String workspaceId = 'shop-A',
    String orderId = 'job-1',
    int revision = 1,
    String currency = 'GBP',
    int labour = 3000,
  }) =>
      GarageQuoteRevision(
        workspaceId: workspaceId,
        orderId: orderId,
        revision: revision,
        currency: currency,
        lines: [
          GarageQuoteLine(
            type: GarageQuoteLineType.labour,
            description: 'Diagnose and repair',
            quantity: 2,
            unitPriceMinor: labour,
            taxMinor: 1200,
          ),
        ],
      );

  GarageWorkOrder started() => const GarageWorkOrder(
        workspaceId: 'shop-A',
        id: 'job-1',
      ).moveTo(
        GarageOrderStatus.diagnosing,
        actor: GarageTeamRole.mechanic,
      );

  GarageWorkOrder waitingApproval() => started()
      .reviseQuote(
        next: quote(),
        actor: GarageTeamRole.serviceAdvisor,
      )
      .moveTo(
        GarageOrderStatus.awaitingApproval,
        actor: GarageTeamRole.serviceAdvisor,
      );

  GarageWorkOrder approved() => waitingApproval().recordApprovedQuote(
        revision: 1,
        kind: GarageQuoteApprovalKind.customer,
      );

  test('a valid work order follows diagnosis, approval and handover', () {
    final order = approved()
        .moveTo(
          GarageOrderStatus.inProgress,
          actor: GarageTeamRole.mechanic,
        )
        .moveTo(
          GarageOrderStatus.ready,
          actor: GarageTeamRole.mechanic,
        )
        .moveTo(
          GarageOrderStatus.collected,
          actor: GarageTeamRole.serviceAdvisor,
        );

    expect(order.status, GarageOrderStatus.collected);
    expect(order.quote!.totalMinor, 7200);
    expect(order.hasCurrentQuoteApproval, isTrue);
  });

  test('diagnosing cannot skip estimate and approval', () {
    final order = started();
    expect(
      () => order.moveTo(
        GarageOrderStatus.awaitingApproval,
        actor: GarageTeamRole.owner,
      ),
      throwsStateError,
    );
    expect(
      () => order.moveTo(
        GarageOrderStatus.inProgress,
        actor: GarageTeamRole.owner,
      ),
      throwsStateError,
    );
  });

  test('mechanics cannot approve, publish estimates, cancel or hand over', () {
    expect(
      () => started().reviseQuote(
        next: quote(),
        actor: GarageTeamRole.mechanic,
      ),
      throwsStateError,
    );
    expect(
      () => started().moveTo(
        GarageOrderStatus.cancelled,
        actor: GarageTeamRole.mechanic,
      ),
      throwsStateError,
    );
    expect(
      () => started()
          .reviseQuote(
            next: quote(),
            actor: GarageTeamRole.owner,
          )
          .moveTo(
            GarageOrderStatus.awaitingApproval,
            actor: GarageTeamRole.mechanic,
          ),
      throwsStateError,
    );
    final ready = approved()
        .moveTo(
          GarageOrderStatus.inProgress,
          actor: GarageTeamRole.mechanic,
        )
        .moveTo(
          GarageOrderStatus.ready,
          actor: GarageTeamRole.mechanic,
        );
    expect(
      () => ready.moveTo(
        GarageOrderStatus.collected,
        actor: GarageTeamRole.mechanic,
      ),
      throwsStateError,
    );
  });

  test('an estimate for another garage or job is always rejected', () {
    for (final estimate in [
      quote(workspaceId: 'shop-B'),
      quote(orderId: 'job-2'),
    ]) {
      expect(
        () => started().reviseQuote(
          next: estimate,
          actor: GarageTeamRole.owner,
        ),
        throwsStateError,
      );
    }
  });

  test('approval is bound to the current estimate revision', () {
    final first = waitingApproval();
    expect(
      () => first.recordApprovedQuote(
        revision: 7,
        kind: GarageQuoteApprovalKind.customer,
      ),
      throwsStateError,
    );
    final updated = approved().reviseQuote(
      next: quote(revision: 2, labour: 4200),
      actor: GarageTeamRole.serviceAdvisor,
    );
    expect(updated.quote!.revision, 2);
    expect(updated.approvedRevision, isNull);
    expect(updated.hasCurrentQuoteApproval, isFalse);
    expect(
      () => updated.moveTo(
        GarageOrderStatus.inProgress,
        actor: GarageTeamRole.mechanic,
      ),
      throwsStateError,
    );
    final reapproved = updated.recordApprovedQuote(
      revision: 2,
      kind: GarageQuoteApprovalKind.fleetManager,
    );
    expect(reapproved.hasCurrentQuoteApproval, isTrue);
    expect(reapproved.quote!.totalMinor, 9600);
  });

  test('quote revision cannot be skipped or reuse a revision number', () {
    for (final revision in [0, 2, 3]) {
      if (revision == 0) {
        expect(() => quote(revision: revision), throwsRangeError);
      } else {
        expect(
          () => started().reviseQuote(
            next: quote(revision: revision),
            actor: GarageTeamRole.owner,
          ),
          throwsStateError,
        );
      }
    }
  });

  test('the estimate currency cannot change between revisions', () {
    expect(
      () => waitingApproval().reviseQuote(
        next: quote(revision: 2, currency: 'EUR'),
        actor: GarageTeamRole.owner,
      ),
      throwsStateError,
    );
  });

  test('work cannot start, await parts or be handed over without approval', () {
    final order = waitingApproval();
    for (final next in [
      GarageOrderStatus.awaitingParts,
      GarageOrderStatus.inProgress,
      GarageOrderStatus.ready,
    ]) {
      expect(
        () => order.moveTo(next, actor: GarageTeamRole.owner),
        throwsStateError,
      );
    }
  });

  test('repairs can pause for parts and resume after approval', () {
    final order = approved()
        .moveTo(
          GarageOrderStatus.awaitingParts,
          actor: GarageTeamRole.mechanic,
        )
        .moveTo(
          GarageOrderStatus.inProgress,
          actor: GarageTeamRole.mechanic,
        )
        .moveTo(
          GarageOrderStatus.awaitingParts,
          actor: GarageTeamRole.mechanic,
        );
    expect(order.status, GarageOrderStatus.awaitingParts);
  });

  test('complete or cancelled work orders cannot be quietly reopened', () {
    final collected = approved()
        .moveTo(
          GarageOrderStatus.inProgress,
          actor: GarageTeamRole.owner,
        )
        .moveTo(
          GarageOrderStatus.ready,
          actor: GarageTeamRole.owner,
        )
        .moveTo(
          GarageOrderStatus.collected,
          actor: GarageTeamRole.owner,
        );
    final cancelled = started().moveTo(
      GarageOrderStatus.cancelled,
      actor: GarageTeamRole.owner,
    );
    for (final order in [collected, cancelled]) {
      expect(
        () => order.moveTo(
          GarageOrderStatus.diagnosing,
          actor: GarageTeamRole.owner,
        ),
        throwsStateError,
      );
      expect(
        () => order.reviseQuote(
          next: quote(revision: 2),
          actor: GarageTeamRole.owner,
        ),
        throwsStateError,
      );
    }
  });

  test('estimate uses integer minor units and immutable lines', () {
    final estimate = quote();
    expect(estimate.subtotalMinor, 6000);
    expect(estimate.taxMinor, 1200);
    expect(estimate.totalMinor, 7200);
    expect(
      () => estimate.lines.add(
        GarageQuoteLine(
          type: GarageQuoteLineType.part,
          description: 'Filter',
          quantity: 1,
          unitPriceMinor: 900,
          taxMinor: 180,
        ),
      ),
      throwsUnsupportedError,
    );
  });

  test('invalid amounts, quantity, empty notes and currency are rejected', () {
    expect(
      () => GarageQuoteLine(
        type: GarageQuoteLineType.part,
        description: ' ',
        quantity: 1,
        unitPriceMinor: 100,
        taxMinor: 0,
      ),
      throwsArgumentError,
    );
    expect(
      () => GarageQuoteLine(
        type: GarageQuoteLineType.part,
        description: 'Part',
        quantity: 0,
        unitPriceMinor: 100,
        taxMinor: 0,
      ),
      throwsRangeError,
    );
    expect(
      () => GarageQuoteLine(
        type: GarageQuoteLineType.part,
        description: 'Part',
        quantity: 1,
        unitPriceMinor: -100,
        taxMinor: 0,
      ),
      throwsArgumentError,
    );
    expect(() => quote(currency: 'gbp'), throwsArgumentError);
    expect(
      () => GarageQuoteRevision(
        workspaceId: 'shop-A',
        orderId: 'job-1',
        revision: 1,
        currency: 'GBP',
        lines: [],
      ),
      throwsArgumentError,
    );
  });

  test('approving an already approved estimate cannot silently overwrite it',
      () {
    expect(
      () => approved().recordApprovedQuote(
        revision: 1,
        kind: GarageQuoteApprovalKind.fleetManager,
      ),
      throwsStateError,
    );
  });
}
