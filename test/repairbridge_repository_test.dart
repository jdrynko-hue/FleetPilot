import 'package:flutter_test/flutter_test.dart';
import 'package:fleetpilot/garage/repairbridge_repository.dart';

const company = '00000000-0000-4000-8000-000000000011';
const workshop = '00000000-0000-4000-8000-000000000022';
const request = '00000000-0000-4000-8000-000000000033';
const issue = '00000000-0000-4000-8000-000000000044';
const order = '00000000-0000-4000-8000-000000000055';

Map<String, Object?> fixture({
  String status = 'sent',
  bool withQuote = false,
}) => {
  'request_id': request,
  'company_id': company,
  'workspace_id': workshop,
  'issue_id': issue,
  'issue_title': 'Brake noise',
  'status': status,
  'shared_description': null,
  'shared_registration': null,
  'work_order_id': status == 'accepted' ? order : null,
  'work_order_status': status == 'accepted' ? 'awaiting_approval' : null,
  'quote': withQuote ? {
    'revision': 2,
    'currency': 'GBP',
    'subtotal_minor': 6000,
    'tax_minor': 1200,
    'total_minor': 7200,
    'approved': false,
    'lines': [
      { 'type': 'labour', 'description': 'Brake repair', 'quantity': 2,
        'unit_price_minor': 3000, 'tax_minor': 1200 }
    ]
  } : null,
  'events': [
    { 'action':'request_sent','details':<String,dynamic>{},
      'at':'2026-10-14T09:25:00+00:00' }
  ]
};

void main() {
  test('minimal consent request has no vehicle PII or commercial quote', () {
    final view = RepairBridgeRepository.parseSnapshot(fixture());
    expect(view.companyId, company);
    expect(view.workspaceId, workshop);
    expect(view.issueId, issue);
    expect(view.workOrderId, isNull);
    expect(view.quote, isNull);
    expect(view.sharedDescription, isNull);
    expect(view.sharedRegistration, isNull);
    expect(view.events.single.action, 'request_sent');
    expect(() => view.events.clear(), throwsUnsupportedError);
    expect(() => view.events.single.details['forged'] = true,
      throwsUnsupportedError);
  });

  test('accepted workshop quote parses exact revision and integer minor units', () {
    final view = RepairBridgeRepository.parseSnapshot(
      fixture(status:'accepted',withQuote:true));
    expect(view.workOrderId, order);
    expect(view.workOrderStatus, 'awaiting_approval');
    expect(view.quote?.revision, 2);
    expect(view.quote?.totalMinor, 7200);
    expect(view.quote?.formatMinor(7200), '£72.00');
    expect(view.quote?.approved, false);
  });

  test('rejects forged tenant IDs, malformed states and stale quote totals', () {
    final accepted = fixture(status:'accepted',withQuote:true);
    for (final altered in <Map<String,Object?>>[
      {'company_id':'not-a-uuid'},
      {'workspace_id':null},
      {'issue_id':'undefined'},
      {'request_id':12},
      {'issue_title':''},
      {'status':'ready'},
      {'work_order_id':null},
      {'work_order_status':'unknown'},
      {'events':<Object>[]},
      {'events':'invalid'},
      {'quote': {'revision':1}},
    ]) {
      expect(() => RepairBridgeRepository.parseSnapshot({
        ...accepted,...altered,
      }),throwsFormatException);
    }
    final forgedQuote = Map<String,Object?>.from(
      accepted['quote']! as Map<String,Object?>);
    forgedQuote['total_minor'] = 9999;
    expect(() => RepairBridgeRepository.parseSnapshot({
      ...accepted,'quote':forgedQuote,
    }), throwsFormatException);
  });

  test('disallows quote before Garage work order and invalid audit', () {
    for (final changed in <Map<String,Object?>>[
      {'quote':fixture(status:'accepted',withQuote:true)['quote']},
      {'work_order_id':order},
      {'events':[
        {'action':'quote_approved','details':<String,Object?>{},
          'at':'2026-10-14T09:25:00Z'}
      ]},
      {'events':[
        {'action':'request_sent','details':<String,Object?>{},
          'at':'not-a-date'}
      ]},
      {'events':[
        {'action':'unknown','details':<String,Object?>{},
          'at':'2026-10-14T09:25:00Z'}
      ]},
      {'events':[
        {'action':'request_sent','details':'text',
          'at':'2026-10-14T09:25:00Z'}
      ]},
    ]) {
      expect(() => RepairBridgeRepository.parseSnapshot({
        ...fixture(),...changed,
      }),throwsFormatException);
    }
  });

  test('rejects malformed identifiers before sending to server', () {
    expect(() => RepairBridgeRepository.requireUuid('1','companyId'),
      throwsArgumentError);
    expect(RepairBridgeRepository.requireUuid(request,'requestId'),request);
  });
}
