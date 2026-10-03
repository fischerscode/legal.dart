import 'dart:io';

import 'package:yaml/yaml.dart';

import '../model/models.dart';

/// Reads a required YAML mapping with file context.
Future<Map<String, Object?>> readYaml(File file) async {
  if (!await file.exists()) {
    throw LegalException(
      'Could not find ${file.path}. Run from a resolved Dart package or specify --project.',
    );
  }
  try {
    return stringMap(
      loadYaml(await file.readAsString(), sourceUrl: file.uri),
      file.path,
    );
  } on YamlException catch (error) {
    throw LegalException('Invalid YAML in ${file.path}: $error');
  }
}

/// Validates string-keyed mappings at an input boundary.
Map<String, Object?> stringMap(Object? value, String context) {
  if (value is! Map) throw LegalException('$context: expected a mapping.');
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw LegalException('$context: keys must be strings.');
    }
    result[entry.key as String] = entry.value;
  }
  return result;
}

/// Validates non-empty string input.
String requireString(Object? value, String context) {
  if (value is! String || value.trim().isEmpty) {
    throw LegalException('$context: expected a non-empty string.');
  }
  return value;
}

/// Validates sequence input without unchecked generic casts.
List<Object?> requireList(Object? value, String context) {
  if (value is! List) throw LegalException('$context: expected a list.');
  return List<Object?>.from(value);
}

/// Rejects unrecognized mapping keys with their context.
void allowedKeys(
  Map<String, Object?> values,
  Set<String> keys,
  String context,
) {
  for (final key in values.keys) {
    if (!keys.contains(key)) {
      throw LegalException('$context.$key: unknown configuration key.');
    }
  }
}
