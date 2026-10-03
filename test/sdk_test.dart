import 'dart:convert';
import 'dart:io';

import 'package:legal/legal.dart';
import 'package:legal/src/cli/runner.dart';
import 'package:legal/src/licenses/reference_texts.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  late Directory workspace;
  late Directory sdk;
  late Directory app;
  final terms = referenceTexts['BSD-3-Clause-dart']!;
  setUp(() async {
    workspace = await fixtureWorkspace();
    app = Directory(p.join(workspace.path, 'app'));
    sdk = await Directory(p.join(app.path, 'build-sdk')).create();
    await File(p.join(sdk.path, 'version')).writeAsString('3.13.4\n');
    await File(p.join(sdk.path, 'LICENSE')).writeAsString(terms);
    await File(p.join(sdk.path, 'NOTICE'))
        .writeAsString('Runtime attribution\n');
    await resolve(app);
  });
  tearDown(() => workspace.delete(recursive: true));

  test(
    'SDK documents preserve terms, version and policy enforcement',
    () async {
      final result = await const LicenseDetector().detectSdk(sdk);
      expect(result.dependency.name, 'dart-sdk');
      expect(result.dependency.version, '3.13.4');
      expect(result.dependency.source, 'sdk');
      expect(result.expression.toString(), 'BSD-3-Clause');
      expect(result.requiresReview, isFalse);
      expect(result.documents.map((d) => d.path), ['LICENSE', 'NOTICE']);
      final report = LicenseReport([result]);
      final text = report.renderThirdPartyLicenses();
      expect(text, contains(terms));
      expect(text, contains('Runtime attribution\n'));
      expect(text, isNot(contains(sdk.path)));
      expect(
        report.check(LicensePolicy(deny: ['BSD-3-Clause'])).isSuccess,
        isFalse,
      );
    },
  );

  test('additional runtime files are classified and not duplicated', () async {
    final extra = await Directory(p.join(sdk.path, 'third_party')).create();
    final license = File(p.join(extra.path, 'LICENSE'));
    await license.writeAsString(referenceTexts['MIT']!);
    final result = await const LicenseDetector().detectSdk(
      sdk,
      additionalFiles: ['LICENSE', 'third_party/LICENSE', license.path],
    );
    expect(result.documents, hasLength(3));
    expect(result.expression.toString(), '(BSD-3-Clause AND MIT)');
    expect(result.requiresReview, isFalse);
    expect(result.documents.last.text, referenceTexts['MIT']);
    await license.writeAsString('Unrecognized runtime terms');
    final unknown = await const LicenseDetector().detectSdk(
      sdk,
      additionalFiles: ['third_party/LICENSE'],
    );
    expect(unknown.requiresReview, isTrue);
    expect(
      () => LicenseReport([unknown]).renderThirdPartyLicenses(),
      throwsA(isA<LegalException>()),
    );
  });

  test('missing evidence cannot silently produce complete output', () async {
    await File(p.join(sdk.path, 'LICENSE')).delete();
    final missing = await const LicenseDetector().detectSdk(sdk);
    expect(missing.requiresReview, isTrue);
    expect(
      () => LicenseReport([missing]).renderThirdPartyLicenses(),
      throwsA(isA<LegalException>()),
    );
    await File(p.join(sdk.path, 'version')).writeAsString('invalid');
    await expectLater(
      const LicenseDetector().detectSdk(sdk),
      throwsA(isA<LegalException>()),
    );
    await File(p.join(sdk.path, 'version')).delete();
    await expectLater(
      const LicenseDetector().detectSdk(sdk),
      throwsA(isA<LegalException>()),
    );
  });

  test(
    'SDK configuration, CLI overrides and generation use project paths',
    () async {
      final config = File(p.join(app.path, 'sdk.yaml'));
      await config.writeAsString(
        'policy: permissive\ninclude_sdk: true\nsdk_path: build-sdk\n',
      );
      final project = await LegalProject.load(app.path, configPath: 'sdk.yaml');
      expect(
        (await project.scan()).packages.map((p) => p.dependency.name),
        contains('dart-sdk'),
      );
      expect(
        (await project.scan(includeSdk: false)).packages
            .map((p) => p.dependency.name),
        isNot(contains('dart-sdk')),
      );
      final output = StringBuffer();
      final errors = StringBuffer();
      expect(
        await runLegal(
          ['generate', '--project', app.path, '--config', 'sdk.yaml'],
          output: output,
          errors: errors,
        ),
        0,
        reason: '$errors',
      );
      final disabled = StringBuffer();
      expect(
        await runLegal([
          'list',
          '--project',
          app.path,
          '--config',
          'sdk.yaml',
          '--no-include-sdk',
          '--json',
        ], output: disabled),
        0,
      );
      expect('$disabled', isNot(contains('dart-sdk')));
      final extra = File(p.join(sdk.path, 'COPYING-runtime'));
      await extra.writeAsString(referenceTexts['MIT']!);
      await config.writeAsString(
        'policy: permissive\ninclude_sdk: true\nsdk_path: missing\nsdk_license_files: [missing]\n',
      );
      final override = StringBuffer();
      expect(
        await runLegal(
          [
            'list',
            '--project',
            app.path,
            '--config',
            'sdk.yaml',
            '--sdk-path',
            'build-sdk',
            '--sdk-license-file',
            'COPYING-runtime',
            '--json',
          ],
          output: override,
          errors: errors,
        ),
        0,
        reason: '$errors',
      );
      expect('$override', contains('COPYING-runtime'));
      await config.writeAsString(
        'policy: permissive\ninclude_sdk: true\nsdk_path: build-sdk\n',
      );
      final generated = await File(p.join(app.path, 'THIRD_PARTY_LICENSES.txt'))
          .readAsString();
      expect(generated, contains('dart-sdk 3.13.4'));
      expect(generated, contains(terms));
      expect(generated, contains('runtime 1.2.3'));
      expect(
        await runLegal(
          [
            'check',
            '--project',
            app.path,
            '--config',
            'sdk.yaml',
            '--sdk-path',
            'missing',
          ],
          output: output,
          errors: errors,
        ),
        2,
      );
      expect(
        await runLegal(
          [
            'check',
            '--project',
            app.path,
            '--include-sdk',
            '--sdk-path',
            'build-sdk',
            '--sdk-license-file',
            'missing',
          ],
          output: output,
          errors: errors,
        ),
        2,
      );
    },
  );

  test(
    'running SDK is discovered automatically and disabled by default',
    () async {
      final project = await LegalProject.load(app.path);
      expect((await project.scan()).packages, hasLength(3));
      final report = await project.scan(includeSdk: true);
      final entry = report.packages.singleWhere(
        (p) => p.dependency.name == 'dart-sdk',
      );
      final runningSdk = File(Platform.resolvedExecutable).parent.parent;
      expect(entry.dependency.root, runningSdk.uri);
      expect(
        entry.dependency.version,
        (await File(p.join(runningSdk.path, 'version')).readAsString()).trim(),
      );
      final output = StringBuffer();
      expect(
        await runLegal([
          'list',
          '--project',
          app.path,
          '--include-sdk',
          '--json',
        ], output: output),
        0,
      );
      final json = jsonDecode('$output') as Map<String, Object?>;
      expect((json['packages']! as List<Object?>), hasLength(4));
    },
  );
}
