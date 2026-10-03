import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';

import '../licenses/expression.dart';
import '../model/models.dart';
import '../policy/policy.dart';
import 'yaml_helpers.dart';

/// Typed project settings from pubspec's legal section or an explicit YAML file.
final class LegalConfig {
  /// Defaults to an empty allowlist and failure on unresolved evidence.
  LegalConfig({
    LicensePolicy? policy,
    this.output = 'THIRD_PARTY_LICENSES.txt',
    this.includeDev = false,
    this.includeSdk = false,
    this.sdkPath,
    this.sdkTarget,
    Iterable<String> sdkLicenseFiles = const [],
  }) : policy = policy ?? LicensePolicy(),
       sdkLicenseFiles = List.unmodifiable(sdkLicenseFiles);

  /// License and package rules.
  final LicensePolicy policy;

  /// Default generated notice path, relative to the selected project.
  final String output;

  /// Whether scans also follow the selected project's dev dependencies.
  final bool includeDev;

  /// Whether to inventory the Dart SDK alongside Pub dependencies.
  final bool includeSdk;

  /// Build SDK directory, absolute or relative to the selected project.
  final String? sdkPath;

  /// Runtime bundle target OS and architecture, defaulting to the host ABI.
  final String? sdkTarget;

  /// Additional SDK license/notice files, absolute or relative to the SDK.
  final List<String> sdkLicenseFiles;

  /// Reads pubspec.yaml by default; [configPath] is an explicit replacement.
  /// No implicit legal.yaml discovery or merging is performed.
  static Future<LegalConfig> load(
    Directory project, {
    String? configPath,
  }) async {
    final file = File(p.join(project.path, configPath ?? 'pubspec.yaml'));
    final document = await readYaml(file);
    final data = configPath == null
        ? document['legal'] ?? <String, Object?>{}
        : document;
    return LegalConfig.fromMap(
      stringMap(data, '${file.path}:legal'),
      context: file.path,
    );
  }

  /// Parses configuration with key-specific diagnostics and typo rejection.
  factory LegalConfig.fromMap(
    Map<String, Object?> data, {
    String context = 'legal',
  }) {
    allowedKeys(data, {
      'policy',
      'output',
      'include_dev',
      'include_sdk',
      'sdk_path',
      'sdk_target',
      'sdk_license_files',
      'licenses',
      'unknown',
      'packages',
    }, context);
    try {
      final preset = data['policy'];
      if (preset != null && preset != 'permissive') {
        throw LegalException('$context.policy: expected permissive');
      }
      final licenses = stringMap(
        data['licenses'] ?? <String, Object?>{},
        '$context.licenses',
      );
      allowedKeys(licenses, {'allow', 'deny'}, '$context.licenses');
      final packages = stringMap(
        data['packages'] ?? <String, Object?>{},
        '$context.packages',
      );
      allowedKeys(packages, {'ignore', 'overrides'}, '$context.packages');
      final overrides = <String, LicenseOverride>{};
      final rawOverrides = stringMap(
        packages['overrides'] ?? <String, Object?>{},
        '$context.packages.overrides',
      );
      for (final entry in rawOverrides.entries) {
        final where = '$context.packages.overrides.${entry.key}';
        final value = stringMap(entry.value, where);
        allowedKeys(value, {
          'reason',
          'versions',
          'allow',
          'expression',
          'licenses',
        }, where);
        final allowed = stringMap(
          value['licenses'] ?? <String, Object?>{},
          '$where.licenses',
        );
        allowedKeys(allowed, {'allow'}, '$where.licenses');
        try {
          overrides[entry.key] = LicenseOverride(
            reason: requireString(value['reason'], '$where.reason'),
            versions: value['versions'] == null
                ? null
                : VersionConstraint.parse(
                    requireString(value['versions'], '$where.versions'),
                  ),
            allow: _bool(value['allow'] ?? false, '$where.allow'),
            expression: value['expression'] == null
                ? null
                : LicenseExpression.parse(
                    requireString(value['expression'], '$where.expression'),
                  ),
            allowedLicenses: _terms(allowed['allow'], '$where.licenses.allow'),
          );
        } on FormatException catch (error) {
          throw LegalException('$where: ${error.message}');
        } on ArgumentError catch (error) {
          throw LegalException('$where: ${error.message}');
        }
      }
      final unknown = data['unknown'] ?? 'deny';
      final action = switch (unknown) {
        'deny' => UnknownLicenseAction.deny,
        'warn' => UnknownLicenseAction.warn,
        'allow' => UnknownLicenseAction.allow,
        _ => throw LegalException(
          '$context.unknown: expected deny, warn, or allow',
        ),
      };
      final includeDev = _bool(
        data['include_dev'] ?? false,
        '$context.include_dev',
      );
      return LegalConfig(
        output: requireString(
          data['output'] ?? 'THIRD_PARTY_LICENSES.txt',
          '$context.output',
        ),
        includeDev: includeDev,
        includeSdk: _bool(data['include_sdk'] ?? false, '$context.include_sdk'),
        sdkPath: data['sdk_path'] == null
            ? null
            : requireString(data['sdk_path'], '$context.sdk_path'),
        sdkTarget: data['sdk_target'] == null
            ? null
            : requireString(data['sdk_target'], '$context.sdk_target'),
        sdkLicenseFiles: _strings(
          data['sdk_license_files'],
          '$context.sdk_license_files',
        ),
        policy: LicensePolicy(
          allow: {
            if (preset == 'permissive') ...LicensePolicy.permissiveLicenses,
            ..._terms(licenses['allow'], '$context.licenses.allow'),
          },
          deny: _terms(licenses['deny'], '$context.licenses.deny'),
          ignore: _strings(packages['ignore'], '$context.packages.ignore'),
          overrides: overrides,
          unknown: action,
        ),
      );
    } on FormatException catch (error) {
      throw LegalException('$context: ${error.message}');
    } on ArgumentError catch (error) {
      throw LegalException('$context: ${error.message}');
    }
  }
  static bool _bool(Object? value, String context) {
    if (value is! bool) {
      throw LegalException('$context: expected true or false');
    }
    return value;
  }

  static List<String> _strings(Object? value, String context) => value == null
      ? []
      : requireList(
          value,
          context,
        ).map((v) => requireString(v, context)).toList();
  static List<String> _terms(Object? value, String context) =>
      _strings(value, context).map((term) {
        try {
          return LicenseTerm(term).toString();
        } on FormatException catch (error) {
          throw LegalException('$context: ${error.message}');
        }
      }).toList();
}
