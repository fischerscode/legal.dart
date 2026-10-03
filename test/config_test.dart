import 'package:legal/legal.dart';
import 'package:test/test.dart';

void main() {
  test('default conservative and preset explicit', () {
    expect(LegalConfig.fromMap({}).policy.allow, isEmpty);
    expect(LegalConfig.fromMap({}).includeSdk, isFalse);
    expect(LegalConfig.fromMap({}).sdkLicenseFiles, isEmpty);
    expect(LegalConfig.fromMap({}).policy.unknown, UnknownLicenseAction.deny);
    expect(
      LegalConfig.fromMap({'policy': 'permissive'}).policy.allow,
      LicensePolicy.permissiveLicenses,
    );
  });
  test('fully typed settings including version-bound override', () {
    final config = LegalConfig.fromMap({
      'policy': 'permissive',
      'output': 'notices.txt',
      'include_dev': true,
      'include_sdk': true,
      'sdk_path': 'build-sdk',
      'sdk_license_files': ['third_party/LICENSE', 'NOTICE-runtime'],
      'unknown': 'warn',
      'licenses': {
        'deny': ['AGPL-3.0-only'],
      },
      'packages': {
        'ignore': ['internal'],
        'overrides': {
          'sample': {
            'reason': 'Approved in #123',
            'versions': '>=1.0.0 <2.0.0',
            'expression': 'MPL-2.0',
            'licenses': {
              'allow': ['MPL-2.0'],
            },
          },
        },
      },
    });
    expect(config.output, 'notices.txt');
    expect(config.includeDev, isTrue);
    expect(config.includeSdk, isTrue);
    expect(config.sdkPath, 'build-sdk');
    expect(config.sdkLicenseFiles, ['third_party/LICENSE', 'NOTICE-runtime']);
    expect(config.policy.overrides['sample']!.appliesTo('1.2.3'), isTrue);
    expect(config.policy.overrides['sample']!.appliesTo('2.0.0'), isFalse);
  });
  final invalid = <Map<String, Object?>>[
    {'unknown': 'ignore'},
    {'include_dev': 'true'},
    {'include_sdk': 'true'},
    {'sdk_path': ''},
    {'sdk_license_files': 'LICENSE'},
    {
      'sdk_license_files': [''],
    },
    {
      'licenses': {'allow': 'MIT'},
    },
    {
      'licenses': {
        'allow': ['MadeUp'],
      },
    },
    {
      'licenses': {
        'allow': ['MIT OR Apache-2.0'],
      },
    },
    {
      'licenses': {
        'deni': ['MIT'],
      },
    },
    {'outpt': 'file.txt'},
    {'policy': 'safe'},
    {
      'packages': {
        'overrides': {
          'foo': {'allow': true},
        },
      },
    },
    {
      'packages': {
        'overrides': {
          'foo': {'reason': '', 'allow': true},
        },
      },
    },
    {
      'packages': {
        'overrides': {
          'foo': {'reason': 'Reviewed', 'versions': 'broken', 'allow': true},
        },
      },
    },
    {
      'packages': {
        'overrides': {
          'foo': {'reason': 'Reviewed'},
        },
      },
    },
    {
      'packages': {
        'overrides': {
          'foo': {
            'reason': 'Reviewed',
            'licenses': {
              'deny': ['MIT'],
            },
          },
        },
      },
    },
  ];
  for (var i = 0; i < invalid.length; i++) {
    test('rejects invalid settings $i with context', () {
      expect(
        () => LegalConfig.fromMap(invalid[i]),
        throwsA(
          isA<LegalException>().having(
            (e) => e.message,
            'context',
            contains('legal'),
          ),
        ),
      );
    });
  }
}
