import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../config/yaml_helpers.dart';
import '../model/models.dart';

/// Discovers resolved packages using pub's local manifests, lockfile and URI map.
final class DependencyScanner {
  /// Creates an offline scanner; no process, network access or resolution occurs.
  const DependencyScanner();

  /// Reads a resolved project. Run `dart pub get` first.
  Future<List<Dependency>> scan(
    Directory project, {
    bool includeDev = false,
  }) async {
    final pubspec = await readYaml(File(p.join(project.path, 'pubspec.yaml')));
    final name = requireString(pubspec['name'], 'pubspec.name');
    final config = await _findConfig(project);
    final locations = _jsonMap(await config.readAsString(), config.path);
    final lock = await readYaml(
      File(p.join(config.parent.parent.path, 'pubspec.lock')),
    );
    final locked = stringMap(
      lock['packages'] ?? <String, Object?>{},
      'pubspec.lock.packages',
    );
    final nodes = <Map<String, Object?>>[];
    for (final raw in requireList(
      locations['packages'],
      'package_config.packages',
    )) {
      final entry = stringMap(raw, 'package_config package');
      final packageName = requireString(entry['name'], 'package_config.name');
      final root = config.uri.resolve(
        requireString(entry['rootUri'], 'package_config.rootUri'),
      );
      if (root.scheme != 'file') {
        throw LegalException('Package "$packageName" has a non-file root URI.');
      }
      final directory = Directory.fromUri(root);
      final manifest = await readYaml(
        File(p.join(directory.path, 'pubspec.yaml')),
      );
      if (manifest['name'] != packageName) {
        throw LegalException(
          'Package "$packageName" has mismatched manifest identity. Run dart pub get.',
        );
      }
      final lockEntry = locked[packageName];
      final isWorkspaceRoot = p.equals(
        p.normalize(directory.absolute.path),
        p.normalize(config.parent.parent.absolute.path),
      );
      if (lockEntry == null &&
          !isWorkspaceRoot &&
          manifest['resolution'] != 'workspace') {
        throw LegalException(
          'Package "$packageName" is missing from pubspec.lock. Run dart pub get.',
        );
      }
      final resolved = lockEntry == null
          ? null
          : stringMap(lockEntry, '$packageName lock entry');
      final version = requireString(
        manifest['version'] ?? '0.0.0',
        '$packageName.version',
      );
      if (resolved != null && resolved['version'] != version) {
        throw LegalException(
          'Package "$packageName" version disagrees with pubspec.lock. Run dart pub get.',
        );
      }
      nodes.add({
        'name': packageName,
        'version': version,
        'source': resolved == null
            ? 'root'
            : requireString(resolved['source'], '$packageName.source'),
        'directDependencies': stringMap(
          manifest['dependencies'] ?? <String, Object?>{},
          '$packageName.dependencies',
        ).keys.toList(),
        'devDependencies': stringMap(
          manifest['dev_dependencies'] ?? <String, Object?>{},
          '$packageName.dev_dependencies',
        ).keys.toList(),
      });
    }
    return fromResolvedData(
      projectName: name,
      graph: {'packages': nodes},
      packageConfig: locations,
      packageConfigUri: config.uri,
      lockPackages: locked,
      includeDev: includeDev,
    );
  }

  /// Interprets pub JSON and URI locations without starting a process.
  /// Useful for embedding and testing; rejects missing nodes and locations.
  List<Dependency> fromResolvedData({
    required String projectName,
    required Map<String, Object?> graph,
    required Map<String, Object?> packageConfig,
    required Uri packageConfigUri,
    Map<String, Object?> lockPackages = const {},
    bool includeDev = false,
  }) {
    if (packageConfig['configVersion'] != 2) {
      throw const LegalException(
        'Unsupported package_config version; expected 2.',
      );
    }
    final nodes = <String, Map<String, Object?>>{};
    for (final raw in requireList(graph['packages'], 'pub deps.packages')) {
      final node = stringMap(raw, 'pub deps package');
      final name = requireString(node['name'], 'pub deps package.name');
      if (nodes.containsKey(name)) {
        throw LegalException('Duplicate graph package "$name".');
      }
      nodes[name] = node;
    }
    final roots = <String, Uri>{};
    for (final raw in requireList(
      packageConfig['packages'],
      'package_config.packages',
    )) {
      final entry = stringMap(raw, 'package_config package');
      final name = requireString(entry['name'], 'package_config.name');
      if (roots.containsKey(name)) {
        throw LegalException('Duplicate package location "$name".');
      }
      final uri = packageConfigUri.resolve(
        requireString(entry['rootUri'], 'package_config.rootUri'),
      );
      if (uri.scheme != 'file') {
        throw LegalException('Package "$name" has a non-file root URI.');
      }
      roots[name] = uri;
    }
    final root = nodes[projectName];
    if (root == null) {
      throw LegalException(
        'Project "$projectName" is absent from pub deps. Run dart pub get.',
      );
    }
    final main = _names(root['directDependencies'], 'directDependencies');
    // These fields are present in supported SDKs; do not guess from kind labels.
    final direct = {
      ...main,
      if (includeDev) ..._names(root['devDependencies'], 'devDependencies'),
    };
    final pending = direct.toList();
    final visited = <String>{projectName};
    final dependencies = <Dependency>[];
    while (pending.isNotEmpty) {
      final name = pending.removeLast();
      if (!visited.add(name)) continue;
      final node = nodes[name];
      final location = roots[name];
      if (node == null || location == null) {
        throw LegalException(
          'Resolved dependency "$name" is missing. Run dart pub get.',
        );
      }
      pending.addAll(
        _names(node['directDependencies'], '$name.directDependencies'),
      );
      final source = requireString(node['source'], '$name.source');
      String? url;
      final locked = lockPackages[name];
      if (source == 'hosted' && locked != null) {
        final entry = stringMap(locked, '$name lock entry');
        final description = entry['description'];
        if (description is Map) {
          final host = stringMap(description, '$name description')['url'];
          if (host is String) {
            url = '${host.replaceFirst(RegExp(r'/+$'), '')}/packages/$name';
          }
        }
      }
      dependencies.add(
        Dependency(
          name: name,
          version: requireString(node['version'], '$name.version'),
          root: location,
          source: source,
          direct: direct.contains(name),
          url: url,
        ),
      );
    }
    dependencies.sort((a, b) => a.name.compareTo(b.name));
    return List.unmodifiable(dependencies);
  }

  List<String> _names(Object? value, String context) => requireList(
    value,
    context,
  ).map((v) => requireString(v, context)).toList();

  Future<File> _findConfig(Directory project) async {
    var current = project.absolute;
    while (true) {
      final file = File(
        p.join(current.path, '.dart_tool', 'package_config.json'),
      );
      if (await file.exists()) return file;
      if (current.parent.path == current.path) break;
      current = current.parent;
    }
    throw const LegalException(
      'Could not find .dart_tool/package_config.json. Run dart pub get first.',
    );
  }

  Map<String, Object?> _jsonMap(String text, String context) {
    try {
      return stringMap(jsonDecode(text), context);
    } on FormatException catch (error) {
      throw LegalException('Invalid JSON in $context: ${error.message}');
    }
  }
}
