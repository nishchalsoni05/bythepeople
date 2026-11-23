import 'package:flutter_test/flutter_test.dart';
import 'package:by_the_people/core/utils/format.dart';
import 'package:by_the_people/domain/entities/models.dart';

void main() {
  test('distance formatting', () {
    expect(km(0.42), '420 m');
    expect(km(2.34), '2.3 km');
  });

  test('person initials', () {
    expect(Person(1, 'Aarav Mehta', 10).initials, 'AM');
  });
}
