import 'dart:io';

import 'package:path/path.dart' as p;

import '../config/yaml_helpers.dart';
import '../model/models.dart';
import 'expression.dart';
import 'reference_texts.dart';

/// Conservative local detection: SPDX declarations or full reference matches.
final class LicenseDetector {
  /// Creates a stateless detector. No network requests are made.
  const LicenseDetector();

  /// Recognizes a complete text, or an explicit SPDX-License-Identifier declaration.
  /// Merely mentioning a license name is insufficient.
  LicenseExpression? identify(String text) {
    final markers = _declarations.allMatches(text).toList();
    if (markers.isNotEmpty) {
      // Multiple declarations can describe distinct source files; do not guess.
      if (markers.length != 1) return null;
      try {
        return LicenseExpression.parse(markers.single.group(1)!);
      } on FormatException {
        return null;
      }
    }
    final normalized = _normalize(text);
    for (final entry in referenceTexts.entries) {
      if (normalized == _normalize(entry.value)) {
        return LicenseExpression.parse(
          entry.key == 'BSD-3-Clause-dart' ? 'BSD-3-Clause' : entry.key,
        );
      }
    }
    return null;
  }

  /// Reads root-level license files and `LICENSES/` (REUSE convention).
  /// UTF-8 decoding and I/O failures are scan errors rather than policy findings.
  Future<PackageLicense> detect(Dependency dependency) async {
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
      final expression = notice ? null : identify(text);
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
    final pubspec = await readYaml(
      File(p.join(directory.path, 'pubspec.yaml')),
    );
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

  String _normalize(String text) {
    var value = text.replaceAll('\r\n', '\n').trim();
    // Only cosmetic titles, copyright holders and enumerator formatting vary.
    // Additional clauses remain present, preventing modified-license matches.
    value = value.replaceFirst(
      RegExp(
        r'^(MIT License|The MIT License(?: \(MIT\))?|BSD [23]-Clause License|ISC License)\s*\n',
        caseSensitive: false,
      ),
      '',
    );
    // Only leading copyright statements are cosmetic metadata. Appended
    // statements remain part of the terms even if they start with Copyright.
    final copyright = RegExp(
      r'^\s*Copyright[^\n]*(?:\n|$)',
      caseSensitive: false,
    );
    while (copyright.hasMatch(value)) {
      value = value.replaceFirst(copyright, '');
    }
    value = value.replaceAll(
      RegExp(r'^\s*(?:[123]\.|\*)\s+', multiLine: true),
      '',
    );
    value = value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    return value.replaceAll(
      RegExp(r'neither the name of .+? nor the names of its contributors'),
      'neither the name of the copyright holder nor the names of its contributors',
    );
  }
}
