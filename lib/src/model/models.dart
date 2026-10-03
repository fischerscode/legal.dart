import '../licenses/expression.dart';

/// A user-facing scan or configuration error, without an internal stack trace.
final class LegalException implements Exception {
  /// Creates an actionable diagnostic.
  const LegalException(this.message);

  /// Human-readable context and recovery advice.
  final String message;
  @override
  String toString() => message;
}

/// A resolved dependency in the selected project's dependency closure.
final class Dependency {
  /// Records the resolved version and location; [source] is pub's source kind.
  const Dependency({
    required this.name,
    required this.version,
    required this.root,
    required this.source,
    required this.direct,
    this.url,
  });

  /// Pub package name.
  final String name;

  /// Resolved version, not the constraint in pubspec.
  final String version;

  /// Local package directory, including resolved path and Git packages.
  final Uri root;

  /// `hosted`, `path`, `git`, `sdk`, or `root`.
  final String source;

  /// Whether this is an immediate selected dependency.
  final bool direct;

  /// Public provenance supplied by package metadata, if available.
  final String? url;
}

/// Whether a document supplies license terms or supplementary notices.
enum LicenseDocumentKind {
  /// License or copying terms.
  license,

  /// Supplementary attribution, preserved but not classified as a license.
  notice,
}

/// A document read from a dependency; its UTF-8 text is preserved verbatim.
final class LicenseDocument {
  /// Creates a document with its package-relative source path.
  const LicenseDocument({
    required this.path,
    required this.text,
    this.kind = LicenseDocumentKind.license,
    this.expression,
  });

  /// Package-relative path, avoiding machine-specific paths in rendered output.
  final String path;

  /// Original decoded text, including copyright notices and line endings.
  final String text;

  /// Purpose of this document.
  final LicenseDocumentKind kind;

  /// Reliably recognized SPDX expression, or null.
  final LicenseExpression? expression;
}

/// License inventory for one dependency, including unresolved evidence.
final class PackageLicense {
  /// Copies lists to keep inventories immutable.
  PackageLicense({
    required this.dependency,
    required Iterable<LicenseDocument> documents,
    this.expression,
    Iterable<String> issues = const [],
    this.metadataExpression,
  }) : documents = List.unmodifiable(documents),
       issues = List.unmodifiable(issues);

  /// Package identity and provenance.
  final Dependency dependency;

  /// All detected license and notice documents.
  final List<LicenseDocument> documents;

  /// Combined license expression; multiple license files imply AND.
  final LicenseExpression? expression;

  /// Metadata declaration, used only when no license document exists.
  final LicenseExpression? metadataExpression;

  /// Missing, unrecognized, empty, or ambiguous evidence requiring review.
  final List<String> issues;

  /// Whether inventory evidence needs manual review.
  bool get requiresReview => expression == null || issues.isNotEmpty;
}
