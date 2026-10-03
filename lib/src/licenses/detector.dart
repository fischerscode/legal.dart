import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';

import '../config/yaml_helpers.dart';
import '../model/models.dart';
import 'expression.dart';
import 'pana_adapter.dart';

/// Local license evidence discovery backed by the pinned pana text matcher.
final class LicenseDetector {
  /// Uses pana's bundled SPDX corpus when running from Dart source.
  /// A compiled executable must supply the corpus via [licenseDataDirectory].
  const LicenseDetector({this.licenseDataDirectory});

  /// Directory containing pana 0.23.19's SPDX license `.txt` files.
  /// Pana caches its corpus per isolate; use one corpus directory per isolate.
  final String? licenseDataDirectory;

  /// Returns candidate SPDX terms from text or an explicit declaration.
  /// Use [detect] to retain review findings for altered or additional text.
  Future<LicenseExpression?> identify(String text) async =>
      (await _identify(text)).expression;

  Future<PanaIdentification> _identify(String text) async {
    final markers = _declarations.allMatches(text).toList();
    if (markers.isNotEmpty) {
      if (markers.length != 1) return PanaIdentification(null, const []);
      try {
        return PanaIdentification(
          LicenseExpression.parse(markers.single.group(1)!),
          const [],
        );
      } on FormatException {
        return PanaIdentification(null, const []);
      }
    }
    return PanaLicenseAdapter(licenseDataDirectory: licenseDataDirectory)
        .identify(text);
  }

  /// Reads root-level license files and `LICENSES/` (REUSE convention).
  /// UTF-8 decoding and I/O failures are scan errors rather than policy findings.
  Future<PackageLicense> detect(Dependency dependency) => _detect(dependency);

  /// Reads SDK root documents and explicitly supplied runtime license files.
  /// The SDK must be the one used to build the distributed application.
  /// Additional paths are absolute or relative to [directory].
  Future<PackageLicense> detectSdk(
    Directory directory, {
    Iterable<String> additionalFiles = const [],
  }) async {
    final versionFile = File(p.join(directory.path, 'version'));
    if (!await versionFile.exists()) {
      throw LegalException(
        'Missing Dart SDK version file: ${versionFile.path}. '
        'Set --sdk-path to the build SDK directory (not the Flutter root).',
      );
    }
    final version = (await versionFile.readAsString()).trim();
    try {
      Version.parse(version);
    } on FormatException {
      throw LegalException(
        'Invalid Dart SDK version in ${versionFile.path}: $version',
      );
    }
    return _detect(
      Dependency(
        name: 'dart-sdk',
        version: version,
        root: directory.absolute.uri,
        source: 'sdk',
        direct: false,
        url: 'https://github.com/dart-lang/sdk',
      ),
      sdk: true,
      additionalFiles: additionalFiles,
    );
  }

  Future<PackageLicense> _detect(
    Dependency dependency, {
    bool sdk = false,
    Iterable<String> additionalFiles = const [],
  }) async {
    final directory = Directory.fromUri(dependency.root);
    final files = <File>[];
    await for (final entity in directory.list(followLinks: true)) {
      final name = p.basename(entity.path);
      if (entity is File && _isDocument(name)) files.add(entity);
      if (entity is Directory && name.toUpperCase() == 'LICENSES') {
        await for (final child in entity.list(followLinks: true)) {
          if (child is File) files.add(child);
        }
      }
    }
    for (final path in additionalFiles) {
      final file = File(
        p.isAbsolute(path) ? path : p.join(directory.path, path),
      );
      if (!await file.exists()) {
        throw LegalException('Missing SDK license file: ${file.path}');
      }
      final resolved = await file.resolveSymbolicLinks();
      var duplicate = false;
      for (final existing in files) {
        if (await existing.resolveSymbolicLinks() == resolved) {
          duplicate = true;
          break;
        }
      }
      if (!duplicate) files.add(file);
    }
    files.sort((a, b) => a.path.compareTo(b.path));
    final docs = <LicenseDocument>[];
    final issues = <String>[];
    LicenseExpression? combined;
    for (final file in files) {
      final text = await file.readAsString();
      final relative = p
          .relative(file.path, from: directory.path)
          .split(p.separator)
          .join('/');
      final notice = p.basename(file.path).toUpperCase().startsWith('NOTICE');
      final identification = notice ? null : await _identify(text);
      final expression = identification?.expression;
      if (identification != null) {
        issues.addAll(
          identification.issues.map((issue) => '$relative: $issue'),
        );
      }
      if (!notice &&
          expression != null &&
          text
              .replaceAll(_declarations, '')
              .replaceAll(RegExp(r'[/#*\s]'), '')
              .isEmpty) {
        issues.add(
          '$relative supplies only an SPDX declaration, not license terms',
        );
      }
      docs.add(
        LicenseDocument(
          path: relative,
          text: text,
          kind: notice
              ? LicenseDocumentKind.notice
              : LicenseDocumentKind.license,
          expression: expression,
        ),
      );
      if (text.trim().isEmpty) issues.add('$relative is empty');
      if (!notice) {
        if (expression == null) {
          issues.add('$relative has unrecognized license terms');
        } else {
          combined = combined == null
              ? expression
              : LicenseAnd(combined, expression);
        }
      }
    }
    final pubspec = sdk
        ? <String, Object?>{}
        : await readYaml(File(p.join(directory.path, 'pubspec.yaml')));
    LicenseExpression? metadata;
    if (pubspec['license'] is String) {
      try {
        metadata = LicenseExpression.parse(pubspec['license']! as String);
      } on FormatException {
        issues.add('pubspec.license is not a recognized SPDX expression');
      }
    }
    if (!docs.any((d) => d.kind == LicenseDocumentKind.license)) {
      combined = metadata;
      issues.add(
        'No license text supplied; review and provide the distribution notice manually',
      );
    }
    final repository = pubspec['repository'] ?? pubspec['homepage'];
    final enriched = Dependency(
      name: dependency.name,
      version: dependency.version,
      root: dependency.root,
      source: dependency.source,
      direct: dependency.direct,
      url: dependency.url ?? (repository is String ? repository : null),
    );
    return PackageLicense(
      dependency: enriched,
      documents: docs,
      expression: combined,
      metadataExpression: metadata,
      issues: issues,
    );
  }

  RegExp get _declarations => RegExp(
    r'^\s*(?://|#|/\*|\*)?\s*SPDX-License-Identifier:\s*(.+?)\s*(?:\*/)?\s*$',
    multiLine: true,
  );

  bool _isDocument(String name) => RegExp(
    r'^(LICENSE|LICENCE|COPYING|NOTICE)([._-].*)?$',
    caseSensitive: false,
  ).hasMatch(name);
}
