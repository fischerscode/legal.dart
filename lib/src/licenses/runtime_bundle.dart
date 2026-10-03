import 'dart:convert';
import 'dart:ffi';

import '../model/models.dart';
import 'expression.dart';
import 'runtime_data.g.dart';

/// Original upstream documents and reviewed identity for a native component.
final class RuntimeLicenseComponent {
  /// Freezes documents without changing their original texts.
  RuntimeLicenseComponent({
    required this.name,
    required this.source,
    required this.expression,
    required Iterable<LicenseDocument> documents,
  }) : documents = List.unmodifiable(documents);

  /// Stable component name within a bundle.
  final String name;

  /// Pinned upstream license source URL.
  final String source;

  /// Reviewed terms; complex upstream terms may use a LicenseRef.
  final LicenseExpression expression;

  /// Original license and notice texts.
  final List<LicenseDocument> documents;

  /// Adds this component to the SDK-versioned runtime inventory.
  PackageLicense inventory(Dependency sdk) => PackageLicense(
    dependency: Dependency(
      name: 'dart-runtime-$name',
      version: sdk.version,
      root: sdk.root,
      source: 'sdk-runtime',
      direct: false,
      url: source,
    ),
    documents: documents,
    expression: expression,
    issues: [
      if (!documents.any((d) => d.kind == LicenseDocumentKind.license))
        'Runtime component has no license text',
      if (documents.any((d) => d.text.trim().isEmpty))
        'Runtime component has empty license or notice text',
    ],
  );
}

/// Exact SDK version and target coverage for a reviewed runtime collection.
final class RuntimeLicenseBundle {
  /// Partial bundles must identify their remaining coverage gaps.
  RuntimeLicenseBundle({
    required this.sdkVersion,
    required Iterable<String> targets,
    required Iterable<RuntimeLicenseComponent> components,
    Iterable<String> coverageIssues = const [],
  }) : targets = Set.unmodifiable(targets),
       components = List.unmodifiable(components),
       coverageIssues = List.unmodifiable(coverageIssues) {
    if (this.targets.isEmpty || this.components.isEmpty) {
      throw ArgumentError('Runtime bundles require targets and components');
    }
  }

  /// Exact SDK version; no semver ranges or fallback to neighboring releases.
  final String sdkVersion;

  /// OS and architecture identifiers such as `linux-x64`.
  final Set<String> targets;

  /// Native components with pinned original texts.
  final List<RuntimeLicenseComponent> components;

  /// Remaining audit gaps; an empty list declares complete bundle coverage.
  final List<String> coverageIssues;
}

/// Offline runtime license catalog embedded in source and compiled executables.
final class RuntimeLicenseCatalog {
  /// Supports injected collections for API users and reproducible tests.
  RuntimeLicenseCatalog(Iterable<RuntimeLicenseBundle> bundles)
    : bundles = List.unmodifiable(bundles) {
    final keys = <String>{};
    for (final bundle in this.bundles) {
      final names = <String>{};
      for (final component in bundle.components) {
        if (!names.add(component.name)) {
          throw ArgumentError('Duplicate runtime component: ${component.name}');
        }
      }
      for (final target in bundle.targets) {
        if (!keys.add('${bundle.sdkVersion}/$target')) {
          throw ArgumentError(
            'Duplicate runtime bundle: ${bundle.sdkVersion}/$target',
          );
        }
      }
    }
  }

  /// Curated collections shipped with this package; no file or network lookup.
  static final RuntimeLicenseCatalog bundled = _loadBundled();

  /// Immutable collections available for exact selection.
  final List<RuntimeLicenseBundle> bundles;

  /// Host OS and architecture; cross-compilation requires an explicit target.
  static String get hostTarget => Abi.current().toString().replaceAll('_', '-');

  /// Returns only an exact version and target match.
  RuntimeLicenseBundle? find(String sdkVersion, String target) {
    for (final bundle in bundles) {
      if (bundle.sdkVersion == sdkVersion && bundle.targets.contains(target)) {
        return bundle;
      }
    }
    return null;
  }

  static RuntimeLicenseCatalog _loadBundled() {
    final records = jsonDecode(runtimeLicenseData) as List<Object?>;
    return RuntimeLicenseCatalog(
      records.map((record) {
        final data = record! as Map<String, Object?>;
        final issues = (data['issues']! as List<Object?>).cast<String>();
        if (data['complete'] != true && issues.isEmpty) {
          throw StateError('Partial runtime bundle has no coverage issues');
        }
        return RuntimeLicenseBundle(
          sdkVersion: data['sdkVersion']! as String,
          targets: (data['targets']! as List<Object?>).cast<String>(),
          coverageIssues: issues,
          components: (data['components']! as List<Object?>).map((record) {
            final component = record! as Map<String, Object?>;
            final expression = LicenseExpression.parse(
              component['expression']! as String,
            );
            return RuntimeLicenseComponent(
              name: component['name']! as String,
              source: component['source']! as String,
              expression: expression,
              documents: (component['documents']! as List<Object?>).map((
                record,
              ) {
                final doc = record! as Map<String, Object?>;
                final kind = LicenseDocumentKind.values.byName(
                  doc['kind']! as String,
                );
                return LicenseDocument(
                  path: doc['path']! as String,
                  text: doc['text']! as String,
                  kind: kind,
                  expression: kind == LicenseDocumentKind.license
                      ? expression
                      : null,
                );
              }),
            );
          }),
        );
      }),
    );
  }
}

/// Coverage is separate from SPDX recognition and cannot be fixed by an override.
final class RuntimeLicenseCoverage {
  /// Missing bundles have no [bundleId] and an explicit diagnostic.
  RuntimeLicenseCoverage({
    required this.sdkVersion,
    required this.target,
    this.bundleId,
    Iterable<String> issues = const [],
  }) : issues = List.unmodifiable(issues) {
    if (bundleId == null && this.issues.isEmpty) {
      throw ArgumentError('Missing runtime bundles require a coverage issue');
    }
  }

  /// SDK version used for selection.
  final String sdkVersion;

  /// Target OS and architecture used for selection.
  final String target;

  /// Matched collection identity, or null for unsupported versions/targets.
  final String? bundleId;

  /// Coverage gaps that remain independent of license policy approval.
  final List<String> issues;

  /// Whether the selected bundle declares complete coverage for its scope.
  bool get isComplete => issues.isEmpty;
}
