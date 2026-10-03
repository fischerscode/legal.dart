import 'package:pub_semver/pub_semver.dart';

import '../licenses/expression.dart';
import '../model/models.dart';

/// Policy treatment of missing or unrecognized evidence.
enum UnknownLicenseAction {
  /// Fail the check (the default).
  deny,

  /// Emit a review warning without failing the check.
  warn,

  /// Explicitly permit unresolved evidence.
  allow,
}

/// Policy outcome for one package.
enum LicenseStatus {
  /// Permitted by the configured policy.
  allowed,

  /// Explicitly prohibited by the configured policy.
  denied,

  /// Unlisted or unresolved license evidence.
  requiresReview,

  /// Excluded by the project owner.
  ignored,
}

/// A reasoned, optionally version-limited package exception.
final class LicenseOverride {
  /// [allow] approves the package irrespective of evidence; [expression]
  /// reclassifies its terms without changing its original documents.
  /// [allowedLicenses] grants term-specific exceptions to global allow/deny.
  LicenseOverride({
    required this.reason,
    this.versions,
    this.allow = false,
    this.expression,
    Iterable<String> allowedLicenses = const [],
  }) : allowedLicenses = Set.unmodifiable(
         allowedLicenses.map((term) => LicenseTerm(term).toString()),
       ) {
    if (reason.trim().isEmpty) {
      throw ArgumentError.value(reason, 'reason', 'Must not be empty');
    }
    if (!allow && expression == null && this.allowedLicenses.isEmpty) {
      throw ArgumentError(
        'An override must approve a package, supply an expression, or allow terms',
      );
    }
    for (final term in this.allowedLicenses) {
      LicenseTerm(term);
    }
  }

  /// Review record, ticket, or rationale.
  final String reason;

  /// Version range within which this exception is valid.
  final VersionConstraint? versions;

  /// Explicit package approval, including unknown evidence.
  final bool allow;

  /// Manually reviewed license expression; original text remains unchanged.
  final LicenseExpression? expression;

  /// Terms approved for this package, taking priority over global deny.
  final Set<String> allowedLicenses;

  /// Whether the resolved version is covered by this exception.
  bool appliesTo(String version) =>
      versions == null || versions!.allows(Version.parse(version));
}

/// Explicit project policy. This evaluates permissions, not legal suitability.
final class LicensePolicy {
  /// Unlisted terms require review. Global deny takes priority over allow.
  LicensePolicy({
    Iterable<String> allow = const [],
    Iterable<String> deny = const [],
    Iterable<String> ignore = const [],
    Map<String, LicenseOverride> overrides = const {},
    this.unknown = UnknownLicenseAction.deny,
  }) : allow = Set.unmodifiable(
         allow.map((term) => LicenseTerm(term).toString()),
       ),
       deny = Set.unmodifiable(
         deny.map((term) => LicenseTerm(term).toString()),
       ),
       ignore = Set.unmodifiable(ignore),
       overrides = Map.unmodifiable(overrides) {
    for (final term in {...this.allow, ...this.deny}) {
      LicenseTerm(term);
    }
  }

  /// Convenience preset: MIT, BSD-2-Clause, BSD-3-Clause, Apache-2.0, ISC.
  /// This name describes license families, not a legal assurance.
  factory LicensePolicy.permissive() =>
      LicensePolicy(allow: permissiveLicenses);

  /// Stable, deliberately narrow convenience allowlist.
  static const permissiveLicenses = {
    'MIT',
    'BSD-2-Clause',
    'BSD-3-Clause',
    'Apache-2.0',
    'ISC',
  };

  /// Globally permitted SPDX terms (WITH terms must be explicitly listed).
  final Set<String> allow;

  /// Globally prohibited SPDX terms; base IDs also deny their WITH variants.
  final Set<String> deny;

  /// Packages omitted from checks and distribution output; children remain scanned.
  final Set<String> ignore;

  /// Package-specific, reasoned exceptions.
  final Map<String, LicenseOverride> overrides;

  /// Handling of missing or unrecognized license evidence.
  final UnknownLicenseAction unknown;

  /// Checks an immutable inventory without performing I/O.
  LicenseCheckResult check(Iterable<PackageLicense> packages) =>
      LicenseCheckResult(packages.map(_evaluate));

  LicenseFinding _evaluate(PackageLicense package) {
    final dependency = package.dependency;
    if (ignore.contains(dependency.name)) {
      return LicenseFinding(
        package,
        LicenseStatus.ignored,
        false,
        'Ignored by project policy',
      );
    }
    final candidate = overrides[dependency.name];
    final override =
        candidate != null && candidate.appliesTo(dependency.version)
        ? candidate
        : null;
    if (override?.allow ?? false) {
      return LicenseFinding(
        package,
        LicenseStatus.allowed,
        false,
        'Package approved: ${override!.reason}',
      );
    }
    final expression = override?.expression ?? package.expression;
    final status = expression == null
        ? LicenseStatus.requiresReview
        : _expression(expression, override);
    if (status == LicenseStatus.denied) {
      return LicenseFinding(package, status, true, 'Denied by license policy');
    }
    if (expression != null && status == LicenseStatus.requiresReview) {
      return LicenseFinding(
        package,
        status,
        true,
        'License is not on the allowlist; requires review',
      );
    }
    // Reclassification resolves recognition issues, but cannot supply missing texts.
    final unresolved = override?.expression == null && package.requiresReview;
    if (unresolved) {
      return switch (unknown) {
        UnknownLicenseAction.deny => LicenseFinding(
          package,
          LicenseStatus.requiresReview,
          true,
          'Unknown or incomplete license evidence: ${package.issues.join('; ')}',
        ),
        UnknownLicenseAction.warn => LicenseFinding(
          package,
          LicenseStatus.requiresReview,
          false,
          'Warning: unknown or incomplete license evidence',
        ),
        UnknownLicenseAction.allow => LicenseFinding(
          package,
          LicenseStatus.allowed,
          false,
          'Unresolved evidence explicitly permitted by policy',
        ),
      };
    }
    return LicenseFinding(
      package,
      status,
      status != LicenseStatus.allowed,
      status == LicenseStatus.allowed
          ? (override == null
                ? 'Allowed by license policy'
                : 'Allowed with override: ${override.reason}')
          : 'License is not on the allowlist; requires review',
    );
  }

  LicenseStatus _expression(
    LicenseExpression expression,
    LicenseOverride? override,
  ) {
    switch (expression) {
      case LicenseTerm():
        final term = expression.toString();
        if (override?.allowedLicenses.contains(term) ?? false) {
          return LicenseStatus.allowed;
        }
        if (deny.contains(term) || deny.contains(expression.id)) {
          return LicenseStatus.denied;
        }
        if (allow.contains(term)) return LicenseStatus.allowed;
        return LicenseStatus.requiresReview;
      case LicenseAnd():
        final left = _expression(expression.left, override);
        final right = _expression(expression.right, override);
        if (left == LicenseStatus.denied || right == LicenseStatus.denied) {
          return LicenseStatus.denied;
        }
        if (left == LicenseStatus.allowed && right == LicenseStatus.allowed) {
          return LicenseStatus.allowed;
        }
        return LicenseStatus.requiresReview;
      case LicenseOr():
        final left = _expression(expression.left, override);
        final right = _expression(expression.right, override);
        if (left == LicenseStatus.allowed || right == LicenseStatus.allowed) {
          return LicenseStatus.allowed;
        }
        if (left == LicenseStatus.denied && right == LicenseStatus.denied) {
          return LicenseStatus.denied;
        }
        return LicenseStatus.requiresReview;
    }
  }
}

/// One auditable policy decision.
final class LicenseFinding {
  /// Creates a finding; [isFailure] controls CI success independently of warnings.
  const LicenseFinding(this.package, this.status, this.isFailure, this.message);

  /// Original inventory and license evidence.
  final PackageLicense package;

  /// Policy classification.
  final LicenseStatus status;

  /// Whether this finding fails the check.
  final bool isFailure;

  /// Human-readable rationale, including any override reason.
  final String message;
}

/// Aggregate result of a policy check.
final class LicenseCheckResult {
  /// Freezes decisions in inventory order.
  LicenseCheckResult(
    Iterable<LicenseFinding> findings, {
    Iterable<String> issues = const [],
  }) : findings = List.unmodifiable(findings),
       issues = List.unmodifiable(issues);

  /// Decisions, including warnings and ignores.
  final List<LicenseFinding> findings;

  /// Inventory coverage issues independent of per-package policy decisions.
  final List<String> issues;

  /// True when no finding fails the configured policy.
  bool get isSuccess =>
      issues.isEmpty && !findings.any((finding) => finding.isFailure);
}
