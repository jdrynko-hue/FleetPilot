import 'package:flutter_test/flutter_test.dart';

import 'package:fleetpilot/garage/repair_bridge_repository.dart';

const requestId='00000000-0000-4000-8000-000000000001';
const companyId='00000000-0000-4000-8000-000000000002';
const workshopId='00000000-0000-4000-8000-000000000003';
const issueId='00000000-0000-4000-8000-000000000004';
const orderId='00000000-0000-4000-8000-000000000005';

Map<String,Object?> quote({int revision=1,bool approved=false}) => {
  'revision': revision,
  'currency': 'GBP',
  'subtotal_minor': 6000,
  'tax_minor': 1200,
  'total_minor': 7200,
  'approved': approved,
  'lines': [
    {'type':'labour','description':'Brake service','quantity':2,
     'unit_price_minor':3000,'tax_minor':1200},
  ],
};

Map<String,Object?> event(String action,String time) => {
  'action':action,
  'details': action == 'quote_approved'
      ? <String,Object?>{'revision':1}
      : action == 'progress_updated'
          ? <String,Object?>{'from':'in_progress','to':'ready'}
          : <String,Object?>{},
  'at':time,
};

Map<String,Object?> snapshot({
  String status='sent',
  String? workOrderId,
  String? orderStatus,
  Object? estimate,
  Object? history,
  Object? assigned = false,
  Object? mechanic = null,
}) => {
  'request_id':requestId,
  'company_id':companyId,
  'workspace_id':workshopId,
  'issue_id':issueId,
  'issue_title':'Brake defect',
  'shared_description':null,
  'shared_registration':null,
  'status':status,
  'work_order_id':workOrderId,
  'work_order_status':orderStatus,
  'mechanic_assigned':workOrderId == null ? null : assigned,
  'mechanic_user_id':mechanic,
  'quote':estimate,
  'events':history ?? [
    event('request_sent','2026-10-14T09:00:00Z'),
  ],
};

void main() {
  test('initial Fleet request discloses only an issue title',(){
    final data=GarageRepairBridgeSnapshot.parse(snapshot());
    expect(data.status,'sent');
    expect(data.issueId,issueId);
    expect(data.title,'Brake defect');
    expect(data.sharedDescription,isNull);
    expect(data.sharedRegistration,isNull);
    expect(data.mechanicAssigned,isNull);
    expect(data.mechanicUserId,isNull);
    expect(data.quote,isNull);
    expect(data.needsFleetApproval,false);
    expect(data.events.single.action,'request_sent');
    expect(()=>data.events.clear(),throwsUnsupportedError);
  });

  test('workshop estimate requires exact independent manager approval',(){
    final data=GarageRepairBridgeSnapshot.parse(snapshot(
      status:'accepted',workOrderId:orderId,
      orderStatus:'awaiting_approval',estimate:quote(),
      history:[
        event('request_sent','2026-10-14T09:00:00Z'),
        event('request_accepted','2026-10-14T09:05:00Z'),
      ],
    ));
    expect(data.workOrderId,orderId);
    expect(data.needsFleetApproval,true);
    expect(data.quote!.revision,1);
    expect(data.quote!.totalMinor,7200);
    expect(data.quote!.formatMinor(data.quote!.totalMinor),'£72.00');
    expect(()=>data.quote!.lines.clear(),throwsUnsupportedError);
  });

  test('approved quote and completed work never request re-approval',(){
    final data=GarageRepairBridgeSnapshot.parse(snapshot(
      status:'accepted',workOrderId:orderId,
      orderStatus:'ready',estimate:quote(approved:true),
      history:[
        event('request_sent','2026-10-14T09:00:00Z'),
        event('request_accepted','2026-10-14T09:01:00Z'),
        event('quote_approved','2026-10-14T09:02:00Z'),
        event('progress_updated','2026-10-14T09:04:00Z'),
      ],
    ));
    expect(data.quote!.approved,true);
    expect(data.needsFleetApproval,false);
    expect(data.events.length,4);
    expect(data.events.last.action,'progress_updated');
    expect(data.events.last.details['to'],'ready');
    expect(data.events[2].details['revision'],1);
    expect(()=>data.events.last.details['to']='forged',throwsUnsupportedError);
  });

  test('rejects stale or forged inconsistencies rather than trusting UI',(){
    for(final item in <Object?>[
      null,[],{},'bad',
      {...snapshot(),'status':'approved'},
      {...snapshot(),'request_id':'wrong'},
      {...snapshot(),'work_order_id':orderId},
      {...snapshot(),'work_order_status':'ready'},
      {...snapshot(),'status':'accepted'},
      {...snapshot(),'quote':quote()},
      snapshot(status:'accepted',workOrderId:orderId,orderStatus:'unverified'),
      snapshot(status:'accepted',workOrderId:orderId,
        orderStatus:'awaiting_approval',estimate:{...quote(),'total_minor':3}),
      snapshot(status:'accepted',workOrderId:orderId,
        orderStatus:'awaiting_approval',estimate:{...quote(),'currency':'XYZ'}),
      {...snapshot(),'events':[]},
      {...snapshot(),'events':[event('wrong','2026-10-14T09:00:00Z')]},
      {...snapshot(),'events':[event('request_sent','not-a-date')]},
      {...snapshot(),'events':[{
        'action':'progress_updated','details':<String,Object?>{},'at':'2026-10-14T09:03:00Z',
      }]},
      {...snapshot(),'events':[event('request_sent','2026-10-14T09:02:00Z'),
                              event('request_accepted','2026-10-14T09:01:00Z')]},
    ]){
      expect(()=>GarageRepairBridgeSnapshot.parse(item),throwsA(isA<Exception>()));
    }
  });

  test('assignment status does not require revealing staff identity to Fleet',(){
    final noStaff = GarageRepairBridgeSnapshot.parse(snapshot(
      status:'accepted',workOrderId:orderId,orderStatus:'diagnosing',
      assigned:false,
    ));
    expect(noStaff.mechanicAssigned, false);
    expect(noStaff.mechanicUserId, isNull);
    final fleet = GarageRepairBridgeSnapshot.parse(snapshot(
      status:'accepted',workOrderId:orderId,orderStatus:'diagnosing',
      assigned:true,
    ));
    expect(fleet.mechanicAssigned, true);
    expect(fleet.mechanicUserId, isNull);
    final garage = GarageRepairBridgeSnapshot.parse(snapshot(
      status:'accepted',workOrderId:orderId,orderStatus:'diagnosing',
      assigned:true,mechanic:issueId,
    ));
    expect(garage.mechanicUserId, issueId);
    for (final forged in [
      snapshot(status:'accepted',workOrderId:orderId,orderStatus:'diagnosing',
        assigned:false,mechanic:issueId),
      snapshot(status:'accepted',workOrderId:orderId,orderStatus:'diagnosing',
        assigned:'yes'),
      snapshot(status:'accepted',workOrderId:orderId,orderStatus:'diagnosing',
        assigned:true,mechanic:'not a uuid'),
      {...snapshot(), 'mechanic_assigned':true},
    ]) {
      expect(() => GarageRepairBridgeSnapshot.parse(forged),
        throwsFormatException);
    }
  });

  test('rejects invalid bridge identifiers before any remote call',(){
    GarageRepairBridgeRepository.requireId(requestId,'requestId');
    expect(()=>GarageRepairBridgeRepository.requireId('not-uuid','requestId'),
      throwsArgumentError);
    expect(()=>GarageRepairBridgeRepository.requireId('','requestId'),
      throwsArgumentError);
    expect(()=>GarageRepairBridgeRepository.requireId('00000000-0000-0000-0000','requestId'),
      throwsArgumentError);
  });
}
