import 'dart:convert';
import 'dart:io';

import 'package:legal/legal.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  final sample = package('MIT', name: 'alpha');
  final second = PackageLicense(
    dependency: Dependency(
      name: 'beta',
      version: '2.0.0',
      root: Directory.systemTemp.uri,
      source: 'hosted',
      direct: false,
      url: 'https://pub.dev/packages/beta',
    ),
    expression: LicenseExpression.parse('Apache-2.0'),
    documents: [
      const LicenseDocument(
        path: 'NOTICE',
        text: 'Copyright 2026 ACME\r\nAttribution\r\n',
        kind: LicenseDocumentKind.notice,
      ),
      const LicenseDocument(
        path: 'LICENSE',
        text: 'Original second license without newline',
      ),
    ],
  );
  test(
    'golden notice output, sorted documents and packages, verbatim notice',
    () {
      final text = LicenseReport([second, sample]).renderThirdPartyLicenses();
      expect(
        text,
        File('test/goldens/third_party_licenses.txt').readAsStringSync(),
      );
      expect(text, LicenseReport([sample, second]).renderThirdPartyLicenses());
      expect(text, contains('Copyright 2026 ACME\r\nAttribution\r\n'));
      expect(text, isNot(contains(Directory.systemTemp.path)));
    },
  );
  test('identical text is not deduplicated', () {
    final text = LicenseReport([sample, package('MIT', name: 'gamma')])
        .renderThirdPartyLicenses();
    expect('Original terms'.allMatches(text).length, 2);
  });
  test(
    'ignored packages omitted from notices but retained in inventory JSON',
    () {
      final report = LicenseReport([sample, second]);
      final policy = LicensePolicy(ignore: ['alpha']);
      expect(
        report.renderThirdPartyLicenses(policy: policy),
        isNot(contains('alpha 1.2.3')),
      );
      final json =
          jsonDecode(report.toJson(policy: policy)) as Map<String, Object?>;
      expect((json['packages']! as List<Object?>).length, 2);
      expect(report.toJson(policy: policy), contains('ignored'));
    },
  );
  test('missing evidence cannot generate a falsely complete notice, even with package approval', () {
    final unknown = PackageLicense(
      dependency: sample.dependency,
      documents: [],
    );
    final report = LicenseReport([unknown]);
    final policy = LicensePolicy(
      overrides: {'alpha': LicenseOverride(allow: true, reason: 'Reviewed')},
    );
    expect(
      () => report.renderThirdPartyLicenses(policy: policy),
      throwsA(isA<LegalException>()),
    );
    expect(
      report.renderThirdPartyLicenses(allowIncomplete: true),
      contains('INCOMPLETE DRAFT'),
    );
  });
  test('expression override does not waive missing original license text', () {
    final unknown = PackageLicense(
      dependency: sample.dependency,
      documents: [],
    );
    final policy = LicensePolicy(
      overrides: {
        'alpha': LicenseOverride(
          expression: LicenseExpression.parse('MIT'),
          reason: 'Reviewed',
        ),
      },
    );
    expect(
      () => LicenseReport([unknown]).renderThirdPartyLicenses(policy: policy),
      throwsA(isA<LegalException>()),
    );
  });
  test('unknown extra document cannot be hidden during generation', () {
    final inventory = package('MIT', issues: ['Unrecognized COPYING']);
    expect(
      () => LicenseReport([inventory]).renderThirdPartyLicenses(),
      throwsA(isA<LegalException>()),
    );
  });
}
