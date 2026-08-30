import 'package:flutter_test/flutter_test.dart';
import 'package:marking_prokect_v2/services/id_factory.dart';

void main() {
  test('ids handed out in a tight loop are all different', () {
    // The real case this guards: importing a roster creates thirty students
    // in one loop, faster than the clock ticks. Two students sharing an id
    // get each other's marked work — in the gradebook, and in their report
    // card comments.
    final ids = <String>{};
    for (var i = 0; i < 1000; i++) {
      ids.add(IdFactory.newId());
    }
    expect(ids.length, 1000);
  });

  test('an id still starts with when it was made', () {
    final before = DateTime.now().microsecondsSinceEpoch;
    final stamp = int.parse(IdFactory.newId().split('-').first);
    expect(stamp, greaterThanOrEqualTo(before));
  });
}
