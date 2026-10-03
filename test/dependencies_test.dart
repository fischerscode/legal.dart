import 'dart:io';
import 'dart:convert';

import 'package:legal/legal.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  late Directory workspace;
  const scanner = DependencyScanner();
  setUpAll(() async {
    workspace = await fixtureWorkspace();
    await resolve(Directory(p.join(workspace.path, 'app')));
    await resolve(Directory(p.join(workspace.path, 'empty')));
  });
  tearDownAll(() => workspace.delete(recursive: true));

  test('real pub graph excludes dev-only transitives and keeps shared dev declarations', () async {
    final deps = await scanner.scan(Directory(p.join(workspace.path, 'app')));
    expect(deps.map((d) => d.name), ['dual', 'runtime', 'shared']);
    expect(deps.singleWhere((d) => d.name == 'runtime').direct, isTrue);
    expect(deps.singleWhere((d) => d.name == 'shared').direct, isFalse);
    expect(deps.every((d) => d.source == 'path'), isTrue);
    expect(Directory.fromUri(deps.first.root).existsSync(), isTrue);
  });
  test(
    'include-dev adds direct dev and dev-only transitive dependencies',
    () async {
      final deps = await scanner.scan(
        Directory(p.join(workspace.path, 'app')),
        includeDev: true,
      );
      expect(deps.map((d) => d.name), [
        'dev',
        'dev_only',
        'dual',
        'runtime',
        'shared',
      ]);
      expect(deps.singleWhere((d) => d.name == 'dual').direct, isTrue);
    },
  );
  test('empty resolved project', () async {
    expect(
      await scanner.scan(Directory(p.join(workspace.path, 'empty'))),
      isEmpty,
    );
  });
  test('symlink path package resolves and preserves its license', () async {
    if (Platform.isWindows) {
      return; // Creating links can require elevated rights.
    }
    final link = Link(p.join(workspace.path, 'linked'));
    await link.create(p.join(workspace.path, 'packages', 'shared'));
    final project = Directory(p.join(workspace.path, 'symlink'))..createSync();
    await File(p.join(project.path, 'pubspec.yaml')).writeAsString(
      'name: symlink_app\nenvironment:\n  sdk: ^3.13.0\ndependencies:\n  shared:\n    path: ../linked\n',
    );
    await resolve(project);
    final deps = await scanner.scan(project);
    final license = await const LicenseDetector().detect(deps.single);
    expect(license.expression.toString(), 'MIT');
  });
  test('real local Git dependency uses checked-out evidence offline', () async {
    final gitRoot = Directory(p.join(workspace.path, 'git-source'));
    await copyDirectory(
      Directory(p.join(workspace.path, 'packages', 'shared')),
      gitRoot,
    );
    Future<void> git(List<String> args) async {
      final result = await Process.run(
        'git',
        args,
        workingDirectory: gitRoot.path,
      );
      expect(result.exitCode, 0, reason: '${result.stderr}');
    }

    await git(['init']);
    await git(['add', '.']);
    await git([
      '-c',
      'user.name=Fixture',
      '-c',
      'user.email=fixture@example.invalid',
      'commit',
      '-m',
      'test: fixture',
    ]);
    final project = Directory(p.join(workspace.path, 'git-app'))..createSync();
    await File(p.join(project.path, 'pubspec.yaml')).writeAsString(
      'name: git_app\nenvironment:\n  sdk: ^3.13.0\ndependencies:\n  shared:\n    git:\n      url: ${gitRoot.uri}\n',
    );
    await resolve(project);
    final deps = await scanner.scan(project);
    expect(deps.single.source, 'git');
    expect(
      (await const LicenseDetector().detect(deps.single)).expression.toString(),
      'MIT',
    );
  });
  test(
    'missing graph and missing location fail rather than omit a dependency',
    () {
      final root = {
        'name': 'app',
        'directDependencies': ['missing'],
        'devDependencies': <String>[],
      };
      final graph = <String, Object?>{
        'packages': [root],
      };
      final config = <String, Object?>{
        'configVersion': 2,
        'packages': <Object?>[],
      };
      expect(
        () => scanner.fromResolvedData(
          projectName: 'app',
          graph: graph,
          packageConfig: config,
          packageConfigUri: Uri.file('/project/.dart_tool/package_config.json'),
        ),
        throwsA(isA<LegalException>()),
      );
    },
  );
  test('workspace selects only the requested root and ignores other roots dev edges', () {
    final graph = <String, Object?>{
      'packages': [
        {
          'name': 'app',
          'directDependencies': ['member'],
          'devDependencies': ['dev'],
        },
        {
          'name': 'member',
          'source': 'root',
          'version': '1.0.0',
          'directDependencies': ['leaf'],
          'devDependencies': ['dev'],
        },
        {
          'name': 'leaf',
          'source': 'hosted',
          'version': '1.0.0',
          'directDependencies': <String>[],
        },
        {
          'name': 'dev',
          'source': 'path',
          'version': '1.0.0',
          'directDependencies': <String>[],
        },
      ],
    };
    final config = <String, Object?>{
      'configVersion': 2,
      'packages': [
        for (final name in ['app', 'member', 'leaf', 'dev'])
          {'name': name, 'rootUri': '../$name'},
      ],
    };
    final deps = scanner.fromResolvedData(
      projectName: 'app',
      graph: graph,
      packageConfig: config,
      packageConfigUri: Uri.file('/project/.dart_tool/package_config.json'),
    );
    expect(deps.map((d) => d.name), ['leaf', 'member']);
  });
  test('missing package configuration gives actionable error', () async {
    final dir = await Directory.systemTemp.createTemp('legal-unresolved-');
    addTearDown(() => dir.delete(recursive: true));
    await File(p.join(dir.path, 'pubspec.yaml'))
        .writeAsString('name: unresolved\n');
    expect(
      () => scanner.scan(dir),
      throwsA(
        isA<LegalException>().having(
          (e) => e.message,
          'message',
          contains('pub get'),
        ),
      ),
    );
  });
  test(
    'pub JSON directDependencies is present in the actual SDK format',
    () async {
      final result = await Process.run(Platform.resolvedExecutable, [
        'pub',
        'deps',
        '--json',
      ], workingDirectory: p.join(workspace.path, 'app'));
      final graph = jsonDecode(result.stdout as String) as Map<String, Object?>;
      expect(
        (graph['packages']! as List<Object?>).every(
          (v) => (v! as Map<String, Object?>).containsKey('directDependencies'),
        ),
        isTrue,
      );
    },
  );
  test(
    'changed path package version fails until resolution is updated',
    () async {
      final temporary = await fixtureWorkspace();
      addTearDown(() => temporary.delete(recursive: true));
      final app = Directory(p.join(temporary.path, 'app'));
      await resolve(app);
      final manifest = File(
        p.join(temporary.path, 'packages', 'shared', 'pubspec.yaml'),
      );
      await manifest.writeAsString(
        (await manifest.readAsString()).replaceFirst(
          'version: 1.2.3',
          'version: 2.0.0',
        ),
      );
      expect(
        () => scanner.scan(app),
        throwsA(
          isA<LegalException>().having(
            (e) => e.message,
            'message',
            contains('pub get'),
          ),
        ),
      );
    },
  );
}
