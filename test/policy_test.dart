import 'package:legal/legal.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  final policy = LicensePolicy(
    allow: ['MIT'],
    deny: ['GPL-3.0-only', 'AGPL-3.0-only'],
  );
  LicenseFinding check(String expression, {LicensePolicy? using}) =>
      (using ?? policy).check([package(expression)]).findings.single;
  test('allowed, denied and unlisted', () {
    expect(check('MIT').status, LicenseStatus.allowed);
    expect(check('AGPL-3.0-only').status, LicenseStatus.denied);
    expect(check('MPL-2.0').status, LicenseStatus.requiresReview);
    expect(check('MPL-2.0').isFailure, isTrue);
  });
  test('deny wins over global allow', () {
    expect(
      check(
        'MIT',
        using: LicensePolicy(allow: ['MIT'], deny: ['MIT']),
      ).status,
      LicenseStatus.denied,
    );
  });
  test('OR chooses an allowed alternative; AND requires all terms', () {
    expect(check('MIT OR GPL-3.0-only').status, LicenseStatus.allowed);
    expect(check('MIT AND GPL-3.0-only').status, LicenseStatus.denied);
    expect(check('MIT AND Apache-2.0').status, LicenseStatus.requiresReview);
    expect(
      check('GPL-3.0-only OR Apache-2.0').status,
      LicenseStatus.requiresReview,
    );
    expect(check('GPL-3.0-only OR AGPL-3.0-only').status, LicenseStatus.denied);
    expect(
      check('(MIT OR GPL-3.0-only) AND MIT').status,
      LicenseStatus.allowed,
    );
  });
  test('WITH must be allowed as a whole; base deny applies', () {
    expect(
      check('MIT WITH Classpath-exception-2.0').status,
      LicenseStatus.requiresReview,
    );
    expect(
      check('GPL-3.0-only WITH Classpath-exception-2.0').status,
      LicenseStatus.denied,
    );
    expect(
      check(
        'GPL-3.0-only WITH Classpath-exception-2.0',
        using: LicensePolicy(
          allow: ['GPL-3.0-only WITH Classpath-exception-2.0'],
        ),
      ).status,
      LicenseStatus.allowed,
    );
  });
  test('package approval bypasses global deny with a review reason', () {
    final result = check(
      'GPL-3.0-only',
      using: LicensePolicy(
        deny: ['GPL-3.0-only'],
        overrides: {
          'sample': LicenseOverride(allow: true, reason: 'Reviewed in #123'),
        },
      ),
    );
    expect(result.status, LicenseStatus.allowed);
    expect(result.message, contains('#123'));
  });
  test(
    'term-specific override takes priority, preserves other requirements',
    () {
      final custom = LicensePolicy(
        allow: ['MIT'],
        deny: ['MPL-2.0'],
        overrides: {
          'sample': LicenseOverride(
            allowedLicenses: ['MPL-2.0'],
            reason: 'Reviewed',
          ),
        },
      );
      expect(
        check('MIT AND MPL-2.0', using: custom).status,
        LicenseStatus.allowed,
      );
      expect(
        check('MPL-2.0 AND Apache-2.0', using: custom).status,
        LicenseStatus.requiresReview,
      );
    },
  );
  test('version-limited exception expires', () {
    final custom = LicensePolicy(
      overrides: {
        'sample': LicenseOverride(
          allow: true,
          versions: VersionConstraint.parse('>=1.2.0 <2.0.0'),
          reason: 'Reviewed version range',
        ),
      },
    );
    expect(custom.check([package('GPL-3.0-only')]).isSuccess, isTrue);
    expect(
      custom.check([package('GPL-3.0-only', version: '2.0.0')]).isSuccess,
      isFalse,
    );
  });
  test('ignore wins and does not need evidence', () {
    final custom = LicensePolicy(ignore: ['sample'], deny: ['MIT']);
    expect(
      custom
          .check([
            package('MIT', issues: ['unknown']),
          ])
          .findings
          .single
          .status,
      LicenseStatus.ignored,
    );
    expect(custom.check([package('MIT')]).isSuccess, isTrue);
  });
  test('unresolved evidence default deny, warn and explicit allow', () {
    for (final action in UnknownLicenseAction.values) {
      final result = LicensePolicy(allow: ['MIT'], unknown: action).check([
        package('MIT', issues: ['extra terms']),
      ]);
      expect(result.isSuccess, action != UnknownLicenseAction.deny);
      expect(
        result.findings.single.status,
        action == UnknownLicenseAction.allow
            ? LicenseStatus.allowed
            : LicenseStatus.requiresReview,
      );
    }
    final unknown = PackageLicense(
      dependency: package('MIT').dependency,
      documents: [],
    );
    expect(policy.check([unknown]).isSuccess, isFalse);
    expect(
      LicensePolicy(
        overrides: {
          'sample': LicenseOverride(allow: true, reason: 'Manual review'),
        },
      ).check([unknown]).isSuccess,
      isTrue,
    );
  });
  test(
    'unknown warn does not turn an unlisted recognized license into a warning',
    () {
      expect(
        LicensePolicy(unknown: UnknownLicenseAction.warn)
            .check([package('MPL-2.0')])
            .isSuccess,
        isFalse,
      );
    },
  );
  test(
    'unknown allowance cannot approve unlisted terms with missing evidence',
    () {
      for (final action in [
        UnknownLicenseAction.warn,
        UnknownLicenseAction.allow,
      ]) {
        expect(
          LicensePolicy(unknown: action).check([
            package('MPL-2.0', issues: ['Missing terms']),
          ]).isSuccess,
          isFalse,
        );
      }
    },
  );
  test('programmatic lists canonicalize legacy SPDX plus notation', () {
    final policy = LicensePolicy(allow: ['GPL-2.0+']);
    expect(policy.allow, {'GPL-2.0-or-later'});
    expect(policy.check([package('GPL-2.0-or-later')]).isSuccess, isTrue);
    expect(
      LicenseOverride(
        reason: 'Reviewed',
        allowedLicenses: ['GPL-2.0+'],
      ).allowedLicenses,
      {'GPL-2.0-or-later'},
    );
  });
  test(
    'reclassification resolves recognition, never invents original documents',
    () {
      final custom = LicensePolicy(
        allow: ['MIT'],
        overrides: {
          'sample': LicenseOverride(
            expression: LicenseExpression.parse('MIT'),
            reason: 'Text reviewed',
          ),
        },
      );
      final inventory = PackageLicense(
        dependency: package('MIT').dependency,
        documents: [
          const LicenseDocument(path: 'LICENSE', text: 'Custom terms'),
        ],
        issues: ['Unrecognized'],
      );
      expect(custom.check([inventory]).isSuccess, isTrue);
      expect(
        LicenseReport([inventory]).renderThirdPartyLicenses(policy: custom),
        contains('Custom terms'),
      );
    },
  );
  test('immutable model collections cannot be modified after construction', () {
    final allow = ['MIT'];
    final custom = LicensePolicy(allow: allow);
    allow.add('GPL-3.0-only');
    expect(custom.allow, {'MIT'});
    expect(() => custom.allow.add('ISC'), throwsUnsupportedError);
    expect(() => LicenseOverride(reason: '', allow: true), throwsArgumentError);
  });
}
