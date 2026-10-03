import 'package:legal/legal.dart';
import 'package:test/test.dart';

void main() {
  for (final term in [
    'MIT',
    'BSD-2-Clause',
    'BSD-3-Clause',
    'Apache-2.0',
    'ISC',
    'MPL-2.0',
    'LGPL-3.0-only',
    'GPL-3.0-only',
    'AGPL-3.0-only',
    'GPL-2.0-or-later',
    'LicenseRef-Internal',
    'DocumentRef-Vendor:LicenseRef-Custom',
  ]) {
    test(
      'SPDX $term',
      () => expect(LicenseExpression.parse(term).toString(), term),
    );
  }
  test('AND has higher precedence than OR', () {
    final expression = LicenseExpression.parse(
      'MIT OR Apache-2.0 AND BSD-3-Clause',
    );
    expect(expression, isA<LicenseOr>());
    expect((expression as LicenseOr).right, isA<LicenseAnd>());
    expect(expression.terms, {'MIT', 'Apache-2.0', 'BSD-3-Clause'});
    expect(
      LicenseExpression.parse(expression.toString()).toString(),
      expression.toString(),
    );
  });
  test('legacy plus notation canonicalizes to or-later', () {
    expect(LicenseExpression.parse('GPL-2.0+').toString(), 'GPL-2.0-or-later');
  });
  for (final invalid in [
    '',
    'MIT OR',
    'MIT AND (Apache-2.0',
    'MIT Apache-2.0',
    'MadeUpLicense',
    'mit',
    'MIT WITH MissingException',
    '(MIT) WITH Classpath-exception-2.0',
    'MIT XOR ISC',
    'OR MIT',
    'LicenseRef-',
    'MIT OR OR ISC',
  ]) {
    test(
      'rejects $invalid',
      () =>
          expect(() => LicenseExpression.parse(invalid), throwsFormatException),
    );
  }
  test('bounded input avoids unbounded parser recursion', () {
    expect(
      () => LicenseExpression.parse('${'(' * 600}MIT${')' * 600}'),
      throwsFormatException,
    );
    expect(() => LicenseTerm('MIT OR ISC'), throwsFormatException);
  });
}
