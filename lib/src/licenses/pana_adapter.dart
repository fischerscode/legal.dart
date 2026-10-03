// pana 0.23.18–0.23.19 has no public standalone detection API. Keep its internal API
// usage in this adapter and review the integration tests before updating it.
// ignore_for_file: implementation_imports, invalid_use_of_visible_for_testing_member
import 'package:pana/src/license_detection/license_detector.dart' as pana;

import '../model/models.dart';
import 'expression.dart';
import 'reference_texts.dart';

/// Internal result; no pana types escape the adapter.
final class PanaIdentification {
  /// Copies review diagnostics alongside the candidate expression.
  PanaIdentification(this.expression, Iterable<String> issues)
    : issues = List.unmodifiable(issues);

  /// Candidate terms; review findings can still prevent policy approval.
  final LicenseExpression? expression;

  /// Unexplained text, altered terms or ambiguous matches.
  final List<String> issues;
}

/// Isolates the tightly constrained pana text matcher from the domain model.
final class PanaLicenseAdapter {
  /// Uses the corpus shipped with pana, or an explicit local corpus for AOT.
  const PanaLicenseAdapter({this.licenseDataDirectory});

  /// An optional directory containing the resolved pana corpus.
  final String? licenseDataDirectory;

  /// Runs pana's matcher and preserves evidence requiring manual review.
  Future<PanaIdentification> identify(String text) async {
    if (text.trim().isEmpty) return PanaIdentification(null, const []);
    final pana.Result result;
    try {
      result = await pana.detectLicense(
        text,
        0.95,
        licenseDataDir: licenseDataDirectory,
      );
    } on StateError catch (error) {
      throw LegalException(
        'Could not load pana license data: $error. For a compiled executable, '
        'provide --license-data (CLI) or LicenseDetector(licenseDataDirectory: ...) '
        'pointing to the resolved pana lib/src/third_party/spdx/licenses.',
      );
    }
    // Match pana's own acceptance limits; similarity is not a legal assurance.
    if (result.matches.isEmpty ||
        result.unclaimedTokenPercentage > 0.5 ||
        result.longestUnclaimedTokenCount >= 50) {
      return PanaIdentification(null, const []);
    }
    // Pana offsets refer to its copyright-stripped input. Its token ranges
    // combine optional-appendix matches; match.start/end alone omit that coverage.
    final input = pana.License.parse(identifier: '', content: text);
    final matches = result.matches.toList()
      ..sort((a, b) {
        final start = a.start.offset.compareTo(b.start.offset);
        return start != 0 ? start : a.identifier.compareTo(b.identifier);
      });
    final terms = matches.map((m) => m.identifier).toSet().toList()..sort();
    LicenseExpression? expression;
    for (final id in terms) {
      final LicenseExpression term;
      try {
        term = LicenseExpression.parse(id);
      } on FormatException {
        return PanaIdentification(null, [
          'pana returned unsupported SPDX ID: $id',
        ]);
      }
      expression = expression == null ? term : LicenseAnd(expression, term);
    }
    final issues = <String>[];
    final knownCosmeticVariant = _knownCosmeticVariant(text);
    var coveredEnd = 0;
    for (final match in matches) {
      final start = input.tokens[match.tokenRange.start].span.start.offset;
      final end = input.tokens[match.tokenRange.end].span.end.offset;
      if (start < coveredEnd) {
        issues.add(
          'pana returned overlapping license matches; review their relationship',
        );
      } else if (!knownCosmeticVariant &&
          !_cosmetic(input.content.substring(coveredEnd, start))) {
        issues.add('Text outside the detected license requires review');
      }
      if (end > coveredEnd) coveredEnd = end;
      // For familiar licenses, known cosmetic variants remain acceptable. The
      // reference comparison only validates differences, never identifies text.
      if (match.confidence < 1 &&
          !knownCosmeticVariant &&
          !_knownCosmeticVariant(input.content.substring(start, end))) {
        issues.add(
          'pana detected ${match.identifier} with changed text; review required',
        );
      }
    }
    if (!knownCosmeticVariant &&
        !_cosmetic(input.content.substring(coveredEnd))) {
      issues.add('Text outside the detected license requires review');
    }
    return PanaIdentification(expression, issues.toSet());
  }

  bool _cosmetic(String text) {
    final stripped = text
        .replaceAll(
          RegExp(
            r'^\s*Copyright\s+(?:\(c\)\s*|©\s*)?\d{4}[^\n]*(?:\n|$)',
            caseSensitive: false,
            multiLine: true,
          ),
          '',
        )
        .replaceAll(
          RegExp(
            r'^\s*(?:MIT License|The MIT License(?: \(MIT\))?|BSD [23]-Clause License|ISC License)\s*$',
            caseSensitive: false,
            multiLine: true,
          ),
          '',
        )
        .replaceAll(
          RegExp(
            r'^\s*All rights reserved\.\s*$',
            caseSensitive: false,
            multiLine: true,
          ),
          '',
        );
    return !RegExp(r'[a-zA-Z0-9]').hasMatch(stripped);
  }

  bool _knownCosmeticVariant(String text) {
    String tokens(String value) =>
        pana.tokenize(_normalize(value)).map((token) => token.value).join(' ');
    final normalized = tokens(text);
    return referenceTexts.values.any((value) => normalized == tokens(value));
  }

  String _normalize(String text) {
    var value = text.replaceAll('\r\n', '\n').trim();
    value = value.replaceFirst(
      RegExp(
        r'^(MIT License|The MIT License(?: \(MIT\))?|BSD [23]-Clause License|ISC License)\s*\n',
        caseSensitive: false,
      ),
      '',
    );
    final copyright = RegExp(
      r'^\s*Copyright[^\n]*(?:\n|$)',
      caseSensitive: false,
    );
    while (copyright.hasMatch(value)) {
      value = value.replaceFirst(copyright, '');
    }
    value = value.replaceFirst(
      RegExp(r'^\s*All rights reserved\.\s*\n', caseSensitive: false),
      '',
    );
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
