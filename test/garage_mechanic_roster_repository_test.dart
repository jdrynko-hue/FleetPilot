import 'package:flutter_test/flutter_test.dart';
import 'package:fleetpilot/garage/resource_calendar_repository.dart';

const mechanicId = '00000000-0000-4000-8000-000000000003';

void main() {
  test('only immutable, known mechanic identity fields cross the UI', () {
    final roster=GarageResourceCalendarRepository.parseMechanics([
      {'user_id':mechanicId,'staff_email':'mechanic@example.test',
       'private_address':'not included in the model'},
    ]);
    expect(roster.single.userId,mechanicId);
    expect(roster.single.email,'mechanic@example.test');
    expect(roster.single.toString(),isNot(contains('private_address')));
    expect(() => roster.clear(),throwsUnsupportedError);
  });

  test('fail closed on malformed or oversized roster responses', () {
    for(final response in <Object?>[
      null,
      <String,Object?>{},
      'wrong',
      <Object?>[123],
      <Map<String,Object?>>[
        {'user_id':'not-a-uuid','staff_email':'mechanic@example.test'}
      ],
      <Map<String,Object?>>[
        {'user_id':mechanicId,'staff_email':null}
      ],
      <Map<String,Object?>>[
        {'user_id':mechanicId,'staff_email':'nonsense'}
      ],
      List.generate(151,(i)=><String,Object?>{
        'user_id':mechanicId,'staff_email':'m@example.test'}),
    ]){
      expect(() => GarageResourceCalendarRepository.parseMechanics(response),
        throwsFormatException);
    }
  });
}
