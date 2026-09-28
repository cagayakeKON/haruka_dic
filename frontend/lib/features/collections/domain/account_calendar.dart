import 'package:timezone/data/latest_all.dart' as time_zone_data;
import 'package:timezone/timezone.dart' as time_zone;

bool _timeZonesInitialized = false;

time_zone.Location _location(String ianaTimeZone) {
  if (!_timeZonesInitialized) {
    time_zone_data.initializeTimeZones();
    _timeZonesInitialized = true;
  }
  return time_zone.getLocation(ianaTimeZone);
}

/// Calendar dates for collection history follow the account's IANA zone.
/// Instants remain UTC; only their calendar-day grouping uses this location.
final class AccountCalendar {
  AccountCalendar(String ianaTimeZone, {DateTime Function()? clock})
    : location = _location(ianaTimeZone),
      clock = clock ?? DateTime.now;

  final time_zone.Location location;
  final DateTime Function() clock;

  DateTime dateAt(DateTime instant) {
    final local = time_zone.TZDateTime.from(instant, location);
    return DateTime(local.year, local.month, local.day);
  }

  DateTime get today => dateAt(clock());

  bool isOnDate(DateTime instant, DateTime date) {
    final local = time_zone.TZDateTime.from(instant, location);
    return local.year == date.year && local.month == date.month && local.day == date.day;
  }

  Duration untilNextMidnight([DateTime? instant]) {
    final now = instant ?? clock();
    final local = time_zone.TZDateTime.from(now, location);
    final nextMidnight = time_zone.TZDateTime(location, local.year, local.month, local.day + 1);
    final remaining = nextMidnight.difference(now);
    return remaining > Duration.zero ? remaining : const Duration(milliseconds: 1);
  }
}
