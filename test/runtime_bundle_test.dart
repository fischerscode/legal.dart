import 'dart:convert';
import 'dart:io';

import 'package:legal/legal.dart';
import 'package:legal/src/cli/runner.dart';
import 'package:legal/src/licenses/reference_texts.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  final catalog = RuntimeLicenseCatalog.bundled;
  test(
    'shipped bundle is pinned, partial and preserves every upstream text',
    () async {
      final bundle = catalog.find('3.13.4', 'linux-x64')!;
      expect(bundle.coverageIssues, isNotEmpty);
      expect(
        bundle.components.map((c) => c.name),
        containsAll([
          'boringssl',
          'icu',
          'zlib',
          'double-conversion',
          'libcxx',
          'libcxxabi',
          'v8-regexp',
        ]),
      );
      expect(catalog.find('3.13.5', 'linux-x64'), isNull);
      expect(catalog.find('3.13.4-dev', 'linux-x64'), isNull);
      expect(catalog.find('3.13.4', 'windows-x64'), isNull);
      final manifest = jsonDecode(
        await File('tool/runtime_licenses/3.13.4/manifest.json').readAsString(),
      ) as Map<String, Object?>;
      final components = (manifest['components']! as List<Object?>)
          .cast<Map<String, Object?>>();
      for (final component in bundle.components) {
        final source = components.singleWhere(
          (c) => c['name'] == component.name,
        );
        expect(component.source, source['source']);
        for (final doc in component.documents) {
          expect(
            doc.text,
            await File(p.join('tool/runtime_licenses', doc.path))
                .readAsString(),
          );
        }
      }
      final notice = LicenseDocument(
        path: 'NOTICE',
        text: 'Original notice\r\n',
        kind: LicenseDocumentKind.notice,
      );
      final component = RuntimeLicenseComponent(
        name: 'example',
        source: 'https://example.invalid/pinned',
        expression: LicenseTerm('MIT'),
        documents: [
          LicenseDocument(
            path: 'LICENSE',
            text: referenceTexts['MIT']!,
            expression: LicenseTerm('MIT'),
          ),
          notice,
        ],
      );
      expect(
        component
            .inventory(
              Dependency(
                name: 'dart-sdk',
                version: '3.13.4',
                root: Directory.current.uri,
                source: 'sdk',
                direct: false,
              ),
            )
            .documents
            .last
            .text,
        'Original notice\r\n',
      );
    },
  );

  late Directory workspace;
  late Directory app;
  late Directory sdk;
  setUp(() async {
    workspace = await fixtureWorkspace();
    app = Directory(p.join(workspace.path, 'app'));
    sdk = await Directory(p.join(app.path, 'sdk')).create();
    await File(p.join(sdk.path, 'version')).writeAsString('3.13.4\n');
    await File(p.join(sdk.path, 'LICENSE'))
        .writeAsString(referenceTexts['BSD-3-Clause-dart']!);
    await resolve(app);
  });
  tearDown(() => workspace.delete(recursive: true));

  test('partial bundle is visible offline and coverage cannot be policy-approved away', () async {
    final project = await LegalProject.load(app.path);
    final report = await project.scan(
      includeSdk: true,
      sdkPath: 'sdk',
      sdkTarget: 'linux-x64',
    );
    expect(report.runtimeCoverage!.isComplete, isFalse);
    expect(
      report.packages.map((p) => p.dependency.name),
      contains('dart-runtime-boringssl'),
    );
    final policy = LicensePolicy(
      unknown: UnknownLicenseAction.allow,
      ignore: report.packages.map((p) => p.dependency.name),
      overrides: {
        'dart-sdk': LicenseOverride(
          expression: LicenseTerm('BSD-3-Clause'),
          reason: 'Recognition reviewed',
        ),
      },
    );
    expect(report.check(policy).isSuccess, isFalse);
    expect(report.check(policy).issues, isNotEmpty);
    expect(
      () => report.renderThirdPartyLicenses(policy: policy),
      throwsA(isA<LegalException>()),
    );
    final draft = report.renderThirdPartyLicenses(allowIncomplete: true);
    expect(draft, contains('INCOMPLETE DRAFT'));
    expect(draft, contains('Coverage: incomplete'));
    expect(draft, contains('UNICODE LICENSE V3'));
    final json = jsonDecode(report.toJson()) as Map<String, Object?>;
    expect(
      (json['sdkRuntimeCoverage']! as Map<String, Object?>)['complete'],
      isFalse,
    );
  });

  test(
    'unknown SDK version or target never falls back to another bundle',
    () async {
      final project = await LegalProject.load(app.path);
      for (final target in ['linux-arm64', 'windows-x64']) {
        final report = await project.scan(
          includeSdk: true,
          sdkPath: 'sdk',
          sdkTarget: target,
        );
        expect(report.runtimeCoverage!.bundleId, isNull);
        expect(report.runtimeCoverage!.issues.single, contains(target));
        expect(report.packages, hasLength(4));
        expect(report.check(LicensePolicy.permissive()).isSuccess, isFalse);
      }
      await File(p.join(sdk.path, 'version')).writeAsString('3.13.5');
      final report = await project.scan(
        includeSdk: true,
        sdkPath: 'sdk',
        sdkTarget: 'linux-x64',
      );
      expect(report.runtimeCoverage!.bundleId, isNull);
      expect(report.runtimeCoverage!.issues.single, contains('3.13.5'));
      expect((await project.scan(includeSdk: false)).runtimeCoverage, isNull);
      await expectLater(
        project.scan(
          includeSdk: true,
          sdkPath: 'sdk',
          sdkTarget: '../linux-x64',
        ),
        throwsA(isA<LegalException>()),
      );
    },
  );

  test(
    'a complete exact bundle renders notices and enforces component licenses',
    () async {
      final component = RuntimeLicenseComponent(
        name: 'fixture',
        source: 'https://example.invalid/revision/LICENSE',
        expression: LicenseTerm('MIT'),
        documents: [
          LicenseDocument(
            path: 'fixture/LICENSE',
            text: referenceTexts['MIT']!,
            expression: LicenseTerm('MIT'),
          ),
          const LicenseDocument(
            path: 'fixture/NOTICE',
            text: 'Original fixture attribution\r\n',
            kind: LicenseDocumentKind.notice,
          ),
        ],
      );
      final project = await LegalProject.load(
        app.path,
        runtimeLicenseCatalog: RuntimeLicenseCatalog([
          RuntimeLicenseBundle(
            sdkVersion: '3.13.4',
            targets: ['linux-x64'],
            components: [component],
          ),
        ]),
      );
      final report = await project.scan(
        includeSdk: true,
        sdkPath: 'sdk',
        sdkTarget: 'linux-x64',
      );
      expect(report.runtimeCoverage!.isComplete, isTrue);
      expect(report.check(LicensePolicy.permissive()).isSuccess, isTrue);
      expect(report.check(LicensePolicy(deny: ['MIT'])).isSuccess, isFalse);
      final text = report.renderThirdPartyLicenses(
        policy: LicensePolicy.permissive(),
      );
      expect(text, isNot(contains('INCOMPLETE DRAFT')));
      expect(text, contains('Original fixture attribution\r\n'));
      expect(text, contains('Coverage: complete'));
      expect(
        report.renderThirdPartyLicenses(policy: LicensePolicy.permissive()),
        text,
      );
    },
  );

  test('CLI target overrides configuration; check and generation flag missing coverage', () async {
    await File(p.join(app.path, 'runtime.yaml')).writeAsString(
      'policy: permissive\ninclude_sdk: true\nsdk_path: sdk\nsdk_target: windows-x64\n',
    );
    final common = ['--project', app.path, '--config', 'runtime.yaml'];
    final out = StringBuffer();
    final errors = StringBuffer();
    expect(
      await runLegal(['check', ...common], output: out, errors: errors),
      1,
    );
    expect('$out', contains('INCOMPLETE SDK RUNTIME COVERAGE'));
    expect(
      await runLegal(['generate', ...common], output: out, errors: errors),
      2,
    );
    expect('$errors', contains('windows-x64'));
    expect(
      await File(p.join(app.path, 'THIRD_PARTY_LICENSES.txt')).exists(),
      isFalse,
    );
    final jsonOut = StringBuffer();
    expect(
      await runLegal([
        'list',
        ...common,
        '--sdk-target',
        'linux-x64',
        '--json',
      ], output: jsonOut),
      0,
    );
    final json = jsonDecode('$jsonOut') as Map<String, Object?>;
    expect(
      (json['sdkRuntimeCoverage']! as Map<String, Object?>)['target'],
      'linux-x64',
    );
    expect('$jsonOut', contains('dart-runtime-icu'));
    expect(
      await runLegal(
        [
          'generate',
          ...common,
          '--sdk-target',
          'linux-x64',
          '--allow-incomplete',
        ],
        output: out,
        errors: errors,
      ),
      0,
    );
    final draft = await File(p.join(app.path, 'THIRD_PARTY_LICENSES.txt'))
        .readAsString();
    expect(draft, contains('Coverage: incomplete'));
    expect(draft, contains('UNICODE LICENSE V3'));
  });
}
