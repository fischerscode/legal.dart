import 'dart:convert';
import 'dart:io';

import 'package:legal/legal.dart';
import 'package:legal/src/cli/runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  late Directory workspace;
  late String project;
  final script = p.absolute('bin/legal.dart');
  final packageConfig = p.absolute('.dart_tool/package_config.json');
  setUpAll(() async {
    workspace = await fixtureWorkspace();
    project = p.join(workspace.path, 'app');
    await resolve(Directory(project));
  });
  tearDownAll(() => workspace.delete(recursive: true));
  Future<ProcessResult> cli(List<String> arguments) => Process.run(
    Platform.resolvedExecutable,
    ['--packages=$packageConfig', script, ...arguments],
  );
  test('help succeeds and invalid arguments return usage code', () async {
    expect((await cli(['--help'])).exitCode, 0);
    expect((await cli(['generate', '--help'])).stdout, contains('include-dev'));
    expect((await cli(['nonsense'])).exitCode, 64);
    expect((await cli(['check', '--bad-flag'])).exitCode, 64);
    expect((await cli(['check', 'extra'])).exitCode, 64);
    expect((await cli(['check', '--output=x'])).exitCode, 64);
    expect((await cli(['check', '--force'])).exitCode, 64);
    expect((await cli(['generate', '--json'])).exitCode, 64);
  });
  test(
    'list and check scan the offline fixture and JSON is machine-readable',
    () async {
      final result = await cli(['list', '--project', project, '--json']);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      final json = jsonDecode(result.stdout as String) as Map<String, Object?>;
      expect((json['packages']! as List<Object?>).length, 3);
      expect((await cli(['check', '--project', project])).exitCode, 0);
      final dev = await cli([
        'list',
        '--project',
        project,
        '--include-dev',
        '--json',
      ]);
      expect(
        ((jsonDecode(dev.stdout as String) as Map<String, Object?>)['packages']!
                as List<Object?>)
            .length,
        5,
      );
    },
  );
  test(
    'generate is deterministic, respects output and preserves NOTICE',
    () async {
      final args = [
        'generate',
        '--project',
        project,
        '--output',
        'generated/notices.txt',
      ];
      expect((await cli([...args, '--force'])).exitCode, 0);
      final file = File(p.join(project, 'generated/notices.txt'));
      final first = await file.readAsBytes();
      expect((await cli([...args, '--force'])).exitCode, 0);
      expect(await file.readAsBytes(), first);
      expect(
        await file.readAsString(),
        contains('Fixture attribution\nCopyright 2026 Example authors\n'),
      );
      expect(await file.readAsString(), isNot(contains('dev_only')));
      expect(
        (await cli([
          'generate',
          '--project',
          project,
          '--output',
          'pubspec.yaml',
        ])).exitCode,
        2,
      );
    },
  );
  test('existing output requires --force without a terminal', () async {
    final file = File(p.join(project, 'existing.txt'));
    await file.writeAsString('Previous contents');
    final args = ['generate', '--project', project, '--output', 'existing.txt'];
    final refused = await cli(args);
    expect(refused.exitCode, 2);
    expect(refused.stderr, contains('Use --force'));
    expect(await file.readAsString(), 'Previous contents');
    expect((await cli([...args, '--force'])).exitCode, 0);
    expect(
      await file.readAsString(),
      startsWith('THIRD-PARTY SOFTWARE LICENSES'),
    );
  });
  test(
    'confirmation can accept or decline; new files and force bypass it',
    () async {
      final file = File(p.join(project, 'confirmed.txt'));
      final args = [
        'generate',
        '--project',
        project,
        '--output',
        'confirmed.txt',
      ];
      var confirmations = 0;
      var accepted = false;
      final errors = StringBuffer();
      Future<int> generate(List<String> arguments) => runLegal(
        arguments,
        output: StringBuffer(),
        errors: errors,
        confirmOverwrite: (path) async {
          expect(path, file.path);
          confirmations++;
          return accepted;
        },
      );
      expect(await generate(args), 0);
      expect(confirmations, 0);
      await file.writeAsString('Keep me');
      expect(await generate(args), 2);
      expect(errors.toString(), contains('Output was not overwritten'));
      expect(await file.readAsString(), 'Keep me');
      accepted = true;
      expect(await generate(args), 0);
      expect(confirmations, 2);
      expect(
        await file.readAsString(),
        startsWith('THIRD-PARTY SOFTWARE LICENSES'),
      );
      expect(await generate([...args, '--force']), 0);
      expect(confirmations, 2);
    },
  );
  test('force can overwrite a project input explicitly', () async {
    final root = await fixtureWorkspace();
    addTearDown(() => root.delete(recursive: true));
    final app = Directory(p.join(root.path, 'app'));
    await resolve(app);
    final result = await cli([
      'generate',
      '--project',
      app.path,
      '--output',
      'pubspec.yaml',
      '--force',
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(
      await File(p.join(app.path, 'pubspec.yaml')).readAsString(),
      startsWith('THIRD-PARTY SOFTWARE LICENSES'),
    );
  });
  test(
    'explicit config replaces pubspec settings and provides CI failure code',
    () async {
      final config = File(p.join(project, 'legal.yaml'));
      await config.writeAsString('licenses:\n  deny:\n    - MIT\n');
      final result = await cli([
        'check',
        '--project',
        project,
        '--config',
        'legal.yaml',
        '--json',
      ]);
      expect(result.exitCode, 1);
      expect(result.stdout, contains('denied'));
      await config.writeAsString('unknown: broken\n');
      expect(
        (await cli(['check', '--project', project, '--config', 'legal.yaml']))
            .exitCode,
        2,
      );
      await config.writeAsString('licenses: [invalid yaml\n');
      final invalid = await cli([
        'check',
        '--project',
        project,
        '--config',
        'legal.yaml',
      ]);
      expect(invalid.exitCode, 2);
      expect(invalid.stderr, contains('Invalid YAML'));
    },
  );
  test(
    'unknown text fails check and generation; explicit draft succeeds',
    () async {
      final root = await fixtureWorkspace();
      addTearDown(() => root.delete(recursive: true));
      final app = Directory(p.join(root.path, 'app'));
      await File(p.join(root.path, 'packages/shared/LICENSE'))
          .writeAsString('Unrecognized terms');
      await resolve(app);
      expect((await cli(['check', '--project', app.path])).exitCode, 1);
      expect((await cli(['generate', '--project', app.path])).exitCode, 2);
      expect(
        (await cli(['generate', '--project', app.path, '--allow-incomplete']))
            .exitCode,
        0,
      );
      expect(
        await File(p.join(app.path, 'THIRD_PARTY_LICENSES.txt')).readAsString(),
        contains('INCOMPLETE DRAFT'),
      );
    },
  );
  test('missing project gives actionable error without stacktrace', () async {
    final result = await cli([
      'check',
      '--project',
      p.join(workspace.path, 'missing'),
    ]);
    expect(result.exitCode, 2);
    expect(result.stderr, contains('Could not find pubspec.yaml'));
    expect(result.stderr, isNot(contains('#0')));
  });
  test('programmatic runner accepts injected output streams', () async {
    final out = StringBuffer();
    final errors = StringBuffer();
    expect(
      await runLegal(
        ['list', '--project', project],
        output: out,
        errors: errors,
      ),
      0,
    );
    expect(out.toString(), contains('runtime'));
    expect(errors.isEmpty, isTrue);
    final loaded = await LegalProject.load(project);
    expect((await loaded.scan()).check(loaded.config.policy).isSuccess, isTrue);
  });
}
