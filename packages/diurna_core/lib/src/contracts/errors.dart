import 'dart:convert';
import 'dart:collection';
import 'package:crypto/crypto.dart';

String entityVersion(Map<String, dynamic> row) {
  final fields = SplayTreeMap<String, dynamic>.from(row)..remove('revision');
  return sha256.convert(utf8.encode(jsonEncode(fields))).toString();
}

class DiurnaException implements Exception {
  const DiurnaException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => '$code: $message';
}

String requiredText(String value, String field) {
  final result = value.trim();
  if (result.isEmpty) {
    throw DiurnaException('VALIDATION', '$field must not be blank');
  }
  return result;
}

DateTime parseDate(String value) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    throw const DiurnaException('VALIDATION', 'Date must be YYYY-MM-DD');
  }
  final date = DateTime.tryParse(value);
  if (date == null || date.toIso8601String().split('T').first != value) {
    throw const DiurnaException('VALIDATION', 'Invalid calendar date');
  }
  return date;
}

/// A missing patch field differs from a field explicitly cleared to null.
class Field<T> {
  const Field.absent() : supplied = false, value = null;
  const Field.set(this.value) : supplied = true;
  final bool supplied;
  final T? value;
  T? or(T? previous) => supplied ? value : previous;
}
