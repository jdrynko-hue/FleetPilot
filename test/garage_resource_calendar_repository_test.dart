import 'package:flutter_test/flutter_test.dart';
import 'package:fleetpilot/garage/resource_calendar_repository.dart';

const id='00000000-0000-4000-8000-000000000101';
const other='00000000-0000-4000-8000-000000000102';
const noticeId='00000000-0000-4000-8000-000000000103';

void main() {
  test('workshop bays parse with immutable, scoped resource fields', () {
    final rows=GarageResourceCalendarRepository.parseResources([
      {'id':id,'display_name':'Inspection Bay','mechanic_user_id':other,
       'active':true,'private_email':'never displayed'},
      {'id':other,'display_name':'Tyre Bay','mechanic_user_id':null,
       'active':false},
    ]);
    expect(rows.length,2);
    expect(rows.first.name,'Inspection Bay');
    expect(rows.first.mechanicUserId,other);
    expect(rows[1].active,false);
    expect(()=>rows.clear(),throwsUnsupportedError);
  });

  test('workshop hours validate ISO weekdays and times', () {
    final h=GarageResourceCalendarRepository.parseHours([
      {'iso_weekday':1,'opens_at':'08:00:00','closes_at':'18:00:00'},
      {'iso_weekday':7,'opens_at':'10:00:00','closes_at':'14:00:00'},
    ]);
    expect(h.first.isoWeekday,1);
    expect(h.last.closesAt,'14:00:00');
    for(final bad in [
      {'iso_weekday':8,'opens_at':'08:00:00','closes_at':'18:00:00'},
      {'iso_weekday':1,'opens_at':'18:00:00','closes_at':'08:00:00'},
      {'iso_weekday':1,'opens_at':'bad','closes_at':'18:00:00'},
    ]){
      expect(()=>GarageResourceCalendarRepository.parseHours([bad]),
        throwsFormatException);
    }
  });

  test('capacity stays reserved during a cancellation request', () {
    final result=GarageResourceCalendarRepository.parseCalendar([
      {'booking_id':id,'resource_id':other,'resource_name':'Bay Two',
       'start_at':'2026-11-11T09:30:00Z','duration_minutes':60,
       'status':'cancellation_requested','customer_name':'Private Customer'},
    ]);
    expect(result.single.holdsCapacity,true);
    expect(result.single.startAt.isUtc,true);
    expect(result.single.status,'cancellation_requested');
    for(final status in ['cancelled','requested','invalid']){
      expect(()=>GarageResourceCalendarRepository.parseCalendar([
        {'booking_id':id,'resource_id':other,'resource_name':'Bay Two',
         'start_at':'2026-11-11T09:30:00Z','duration_minutes':60,
         'status':status,'customer_name':'Person'},
      ]),throwsFormatException);
    }
  });

  test('private notifications parse without message bodies or PII', () {
    final result=GarageResourceCalendarRepository.parseNotifications([
      {'id':noticeId,'booking_id':id,'event_action':'confirmed',
       'occurred_at':'2026-10-14T10:00:00Z','read_at':null,
       'private_vehicle_registration':'must_not_show'},
    ]);
    expect(result.single.unread,true);
    expect(result.single.bookingId,id);
    expect(result.single.event,'confirmed');
    expect(()=>result.clear(),throwsUnsupportedError);
    expect(result.single.toString(),isNot(contains('must_not_show')));
    for(final failure in [
      {'event_action':'unknown'},
      {'id':'bad-id'},
      {'read_at':'invalid date'},
    ]){
      expect(()=>GarageResourceCalendarRepository.parseNotifications([
       {'id':noticeId,'booking_id':id,'event_action':'confirmed',
       'occurred_at':'2026-10-14T10:00:00Z','read_at':null,
       ...failure},
      ]),throwsFormatException);
    }
  });

  test('never trusts raw responses with invalid identifiers', () {
    expect(()=>GarageResourceCalendarRepository.validatedId('wrong'),
      throwsArgumentError);
    expect(()=>GarageResourceCalendarRepository.parseResources([
       {'id':'wrong','display_name':'Bay Two','active':true}
    ]),throwsFormatException);
    for(final invalid in <Object?>[null,{},'unexpected',[42]]){
      expect(()=>GarageResourceCalendarRepository.parseNotifications(invalid),
        throwsFormatException);
    }
  });
}
