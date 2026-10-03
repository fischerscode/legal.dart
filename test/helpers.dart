import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:legal/legal.dart';

/// Copies checked-in fixtures, resolving only local packages offline.
Future<Directory> fixtureWorkspace() async {
  final temp = await Directory.systemTemp.createTemp('legal-fixtures-');
  await copyDirectory(Directory('test/fixtures'), temp);
  return temp;
}

/// Copies directories without carrying generated pub files.
Future<void> copyDirectory(Directory source, Directory target) async {
  await target.create(recursive: true);
  await for (final entity in source.list()) {
    final name = p.basename(entity.path);
    if (name == '.dart_tool' || name == 'pubspec.lock') continue;
    final path = p.join(target.path, name);
    if (entity is File) await entity.copy(path);
    if (entity is Directory) await copyDirectory(entity, Directory(path));
  }
}

/// Resolves fixtures without network access.
Future<void> resolve(Directory project) async {
  final result = await Process.run(Platform.resolvedExecutable, [
    'pub',
    'get',
    '--offline',
  ], workingDirectory: project.path);
  if (result.exitCode != 0) {
    throw StateError('${result.stdout}\n${result.stderr}');
  }
}

/// An immutable policy-test inventory with complete synthetic evidence.
PackageLicense package(
  String expression, {
  String name = 'sample',
  String version = '1.2.3',
  List<String> issues = const [],
}) {
  final parsed = LicenseExpression.parse(expression);
  return PackageLicense(
    dependency: Dependency(
      name: name,
      version: version,
      root: Directory.systemTemp.uri,
      source: 'path',
      direct: true,
    ),
    expression: parsed,
    issues: issues,
    documents: [
      LicenseDocument(
        path: 'LICENSE',
        text: 'Original terms\n',
        expression: parsed,
      ),
    ],
  );
}
