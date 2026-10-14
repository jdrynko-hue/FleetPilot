import 'package:flutter_test/flutter_test.dart';
import 'package:fleetpilot/garage/consumer_booking_repository.dart';

const shop='00000000-0000-4000-8000-000000000101';
const booking='00000000-0000-4000-8000-000000000102';
const order='00000000-0000-4000-8000-000000000103';

Map<String,Object?> listing() => {
 'workspace_id':shop,'name':'Independent Garage',
 'city':'Dunstable','country':'GB','time_zone':'Europe/London',
 'services':['brakes','diagnostics']
};

Map<String,Object?> summary({String status='requested',String? orderId}) => {
 'id':booking,'workspace_id':shop,'workshop_name':'Independent Garage',
 'start_at':'2026-11-14T10:00:00+00:00','status':status,
 'service':'brakes','work_order_id':orderId
};

Map<String,Object?> inbox({String status='requested'}) => {
 'id':booking,'customer_name':'Private Customer','customer_email':'private@example.test',
 'vehicle_make':'Ford','vehicle_model':'Focus','registration':null,
 'service':'brakes','concern':'Brakes are noisy',
 'start_at':'2026-11-14T10:00:00+00:00','duration_minutes':60,
 'status':status
};

void main(){
 test('workshop directory only shows typed public metadata',(){
  final result=GarageBookingRepository.parseWorkshops([{
   ...listing(),'private_customer_email':'should not appear'
  }]);
  expect(result,hasLength(1));
  expect(result.single.city,'Dunstable');
  expect(result.single.services,contains('brakes'));
  expect(()=>result.clear(),throwsUnsupportedError);
  expect(()=>result.single.services.clear(),throwsUnsupportedError);
  expect(result.single.toString(),isNot(contains('private_customer_email')));
 });

 test('pending preference is not a confirmed reservation',(){
  final result=GarageBookingRepository.parseMyRequests([summary()]);
  expect(result.single.isOnlyRequested,true);
  expect(result.single.isConfirmed,false);
  expect(result.single.workOrderId,isNull);
  expect(result.single.startAt.isUtc,true);
 });

 test('confirmed booking identifies separate work order',(){
  final result=GarageBookingRepository.parseMyRequests([
   summary(status:'confirmed',orderId:order)
  ]);
  expect(result.single.isConfirmed,true);
  expect(result.single.workOrderId,order);
 });

 test('withdrawal and cancellation remain distinct states',(){
  for(final status in <String>[
   'withdrawn','cancellation_requested','cancelled','declined',
  ]){
   final rows=GarageBookingRepository.parseMyRequests([summary(status:status)]);
   expect(rows,hasLength(1));
   expect(rows.single.isConfirmed,false);
  }
 });

 test('garage inbox validates customer and time, not leak unknown extras',(){
  final rows=GarageBookingRepository.parseInbox([{
   ...inbox(),'stripe_key':'should never display'
  }]);
  expect(rows.single.customerName,'Private Customer');
  expect(rows.single.durationMinutes,60);
  expect(rows.single.registration,isNull);
  expect(rows.single.toString(),isNot(contains('stripe_key')));
 });

 test('unknown statuses, timestamps, services, ids and durations fail closed',(){
  for(final altered in <Map<String,Object?>>[
   {'workspace_id':'not-a-uuid'},
   {'services':['invalid']},
   {'services':[]},
   {'services':'brakes'},
   {'name':''},
   {'time_zone':null},
  ]){
   expect(()=>GarageBookingRepository.parseWorkshops([{...listing(),...altered}]),
    throwsFormatException);
  }
  for(final altered in <Map<String,Object?>>[
   {'id':'not-a-uuid'}, {'status':'already_paid'},
   {'start_at':'not a date'}, {'service':'unknown'},
   {'work_order_id':'bad id'},
  ]){
   expect(()=>GarageBookingRepository.parseMyRequests([{...summary(),...altered}]),
    throwsFormatException);
  }
  for(final altered in <Map<String,Object?>>[
   {'customer_email':null},{'duration_minutes':0},
   {'duration_minutes':30.5},{'registration':123},
   {'status':'price_approved_without_customer'},
  ]){
   expect(()=>GarageBookingRepository.parseInbox([{...inbox(),...altered}]),
    throwsFormatException);
  }
  for(final payload in <Object?>[null,'bad',{},123,[1]]){
   expect(()=>GarageBookingRepository.parseWorkshops(payload),
    throwsFormatException);
  }
 });
}
