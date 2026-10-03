import 'dart:convert';

import '../model/models.dart';
import '../policy/policy.dart';

/// Immutable, sorted inventory that can be checked and rendered without I/O.
final class LicenseReport {
  /// Sorts by package name so scan traversal order never affects output.
  LicenseReport(Iterable<PackageLicense> packages)
    : packages = List.unmodifiable(
        packages.toList()
          ..sort((a, b) => a.dependency.name.compareTo(b.dependency.name)),
      );

  /// All scanned packages, including those subsequently ignored by a policy.
  final List<PackageLicense> packages;

  /// Applies a project policy to this inventory.
  LicenseCheckResult check(LicensePolicy policy) => policy.check(packages);

  /// Renders complete original documents without deduplication or timestamps.
  /// Ignored packages are omitted when [policy] is provided.
  /// Throws [LegalException] on unresolved evidence unless [allowIncomplete]
  /// explicitly permits a visibly marked draft. Overrides never invent text.
  String renderThirdPartyLicenses({
    LicensePolicy? policy,
    bool allowIncomplete = false,
  }) {
    final selected = packages
        .where((p) => !(policy?.ignore.contains(p.dependency.name) ?? false))
        .toList();
    final incomplete = selected.where((p) => !_complete(p, policy)).toList();
    if (!allowIncomplete && incomplete.isNotEmpty) {
      throw LegalException(
        'Cannot generate a complete notice: ${incomplete.map((p) => p.dependency.name).join(', ')} '
        'requires review. Supply missing license texts and review unrecognized terms, '
        'or use --allow-incomplete to produce a marked draft.',
      );
    }
    final out = StringBuffer(
      'THIRD-PARTY SOFTWARE LICENSES\n\nThis product includes third-party software.\n',
    );
    if (incomplete.isNotEmpty) {
      out.writeln(
        '\nINCOMPLETE DRAFT: unresolved license evidence requires manual review.',
      );
    }
    for (final package in selected) {
      final dep = package.dependency;
      final override = _override(package, policy);
      out.write('\n${'=' * 79}\n${dep.name} ${dep.version}\n');
      out.writeln(
        'License: ${override?.expression ?? package.expression ?? 'unknown'}',
      );
      out.writeln('Dependency source: ${dep.source}');
      if (dep.url != null) out.writeln('Source: ${dep.url}');
      if (override != null) out.writeln('Policy override: ${override.reason}');
      if (!_complete(package, policy)) {
        out.writeln('REQUIRES REVIEW: ${package.issues.join('; ')}');
      }
      out.writeln('=' * 79);
      final documents = package.documents.toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      for (final document in documents) {
        out.write('\n--- ${document.path} ---\n\n');
        out.write(document.text);
        if (!document.text.endsWith('\n')) out.writeln();
      }
    }
    return out.toString();
  }

  /// Stable machine-readable inventory, with original text and policy findings.
  String toJson({LicensePolicy? policy}) {
    final decisions = policy == null
        ? <String, LicenseFinding>{}
        : {
            for (final f in check(policy).findings)
              f.package.dependency.name: f,
          };
    return const JsonEncoder.withIndent('  ').convert({
      'schemaVersion': 1,
      'packages': [
        for (final package in packages)
          {
            'name': package.dependency.name,
            'version': package.dependency.version,
            'source': package.dependency.source,
            'direct': package.dependency.direct,
            'url': package.dependency.url,
            'expression': package.expression?.toString(),
            'metadataExpression': package.metadataExpression?.toString(),
            'requiresReview': package.requiresReview,
            'issues': package.issues,
            'documents': [
              for (final doc in package.documents)
                {
                  'path': doc.path,
                  'kind': doc.kind.name,
                  'expression': doc.expression?.toString(),
                  'text': doc.text,
                },
            ],
            if (decisions[package.dependency.name] case final finding?)
              'policy': {
                'status': finding.status.name,
                'isFailure': finding.isFailure,
                'message': finding.message,
              },
          },
      ],
    });
  }

  LicenseOverride? _override(PackageLicense package, LicensePolicy? policy) {
    final override = policy?.overrides[package.dependency.name];
    return override != null && override.appliesTo(package.dependency.version)
        ? override
        : null;
  }

  bool _complete(PackageLicense package, LicensePolicy? policy) {
    if (package.documents
            .where((d) => d.kind == LicenseDocumentKind.license)
            .any((d) => d.text.trim().isEmpty) ||
        !package.documents.any((d) => d.kind == LicenseDocumentKind.license)) {
      return false;
    }
    if (package.documents.any((d) => d.text.trim().isEmpty)) return false;
    return !package.requiresReview ||
        _override(package, policy)?.expression != null;
  }
}
