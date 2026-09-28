import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/features/collections/domain/account_calendar.dart';

void main() {
  test('injected clock changes today at the account midnight, not device midnight', () {
    var now = DateTime.utc(2026, 9, 27, 14, 59, 59);
    final tokyo = AccountCalendar('Asia/Tokyo', clock: () => now);
    expect((tokyo.today.year, tokyo.today.month, tokyo.today.day), (2026, 9, 27));
    expect(tokyo.untilNextMidnight(), const Duration(seconds: 1));
    now = DateTime.utc(2026, 9, 27, 15);
    expect((tokyo.today.year, tokyo.today.month, tokyo.today.day), (2026, 9, 28));
    expect(tokyo.isOnDate(now, DateTime(2026, 9, 28)), isTrue);
    expect(
      tokyo.isOnDate(now.subtract(const Duration(milliseconds: 1)), DateTime(2026, 9, 28)),
      isFalse,
    );

    final shanghai = AccountCalendar('Asia/Shanghai');
    expect(shanghai.isOnDate(now, DateTime(2026, 9, 27)), isTrue);
    expect(AccountCalendar('UTC').isOnDate(now, DateTime(2026, 9, 27)), isTrue);
  });

  test('New York DST spring day is 23 hours and fall day is 25 hours', () {
    final newYork = AccountCalendar('America/New_York');
    final springMidnight = DateTime.utc(2026, 3, 8, 5);
    expect(newYork.untilNextMidnight(springMidnight), const Duration(hours: 23));
    expect(newYork.isOnDate(DateTime.utc(2026, 3, 9, 3, 59, 59), DateTime(2026, 3, 8)), isTrue);
    expect(newYork.isOnDate(DateTime.utc(2026, 3, 9, 4), DateTime(2026, 3, 8)), isFalse);

    final fallMidnight = DateTime.utc(2026, 11, 1, 4);
    expect(newYork.untilNextMidnight(fallMidnight), const Duration(hours: 25));
    expect(newYork.isOnDate(DateTime.utc(2026, 11, 2, 4, 59, 59), DateTime(2026, 11, 1)), isTrue);
    expect(newYork.isOnDate(DateTime.utc(2026, 11, 2, 5), DateTime(2026, 11, 1)), isFalse);
  });

  test('IANA region rules are applied outside the three former fixed-offset zones', () {
    final berlin = AccountCalendar('Europe/Berlin');
    expect(berlin.isOnDate(DateTime.utc(2026, 7, 1, 22), DateTime(2026, 7, 2)), isTrue);
    expect(berlin.isOnDate(DateTime.utc(2026, 1, 1, 22), DateTime(2026, 1, 2)), isFalse);
  });
}
