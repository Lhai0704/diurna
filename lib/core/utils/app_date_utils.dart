import 'package:intl/intl.dart';

class AppDateUtils {
  const AppDateUtils._();

  static final date = DateFormat('yyyy-MM-dd');
  static final dateTime = DateFormat('yyyy-MM-dd HH:mm');

  static String formatDate(DateTime value) => date.format(value.toLocal());

  static String formatDateTime(DateTime value) =>
      dateTime.format(value.toLocal());

  static DateTime? parseNullable(String value) {
    if (value.trim().isEmpty) {
      return null;
    }
    return DateTime.tryParse(value.trim());
  }
}
