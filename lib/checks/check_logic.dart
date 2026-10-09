/// Returns null until every walkaround item has been explicitly assessed.
/// This is only a client-side convenience: the database validates the record.
String? driverCheckResult(Map<String, bool?> answers, {bool unsafe = false}) {
  if (answers.isEmpty || answers.values.any((value) => value == null)) {
    return null;
  }
  if (answers.values.any((value) => value == false)) {
    return unsafe ? 'unsafe' : 'defect';
  }
  return 'pass';
}

const driverCheckItems = <String>[
  'tyres',
  'brakes',
  'lights',
  'mirrors',
  'windscreen',
  'fluids',
  'body',
  'seatbelts',
  'load',
];
