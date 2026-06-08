import 'package:intl/intl.dart';

class TimestampUtils {
  static const int minEpochMilliseconds = 1000000000000;
  static const int minEpochSeconds = 1000000000;
  static const Duration afghanistanOffset = Duration(hours: 4, minutes: 30);

  static int? normalizeEpochMilliseconds(Object? value) {
    final number = _parseNumber(value);
    if (number == null || number <= 0) {
      return null;
    }

    if (number >= minEpochMilliseconds) {
      return number.round();
    }

    if (number >= minEpochSeconds) {
      return (number * 1000).round();
    }

    return null;
  }

  static DateTime? toLocalDateTime(Object? value) {
    final millis = normalizeEpochMilliseconds(value);
    if (millis == null) {
      return null;
    }

    return DateTime.fromMillisecondsSinceEpoch(millis).toLocal();
  }

  static DateTime? toAfghanistanDateTime(Object? value) {
    final millis = normalizeEpochMilliseconds(value);
    if (millis == null) {
      return null;
    }

    return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true)
        .add(afghanistanOffset);
  }

  static String formatAfghanistan(
    Object? value, {
    String pattern = 'MMM dd, yyyy - hh:mm:ss a',
  }) {
    final date = toAfghanistanDateTime(value);
    if (date == null) {
      return '--';
    }

    return DateFormat(pattern).format(date);
  }

  static num? _parseNumber(Object? value) {
    if (value is num) {
      return value;
    }

    return num.tryParse(value?.toString() ?? '');
  }
}
