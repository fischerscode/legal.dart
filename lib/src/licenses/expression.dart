import 'spdx_ids.dart';

/// Parsed SPDX syntax. AND binds more tightly than OR; WITH binds to an ID.
sealed class LicenseExpression {
  const LicenseExpression();

  /// Parses SPDX IDs, LicenseRef IDs, parentheses, AND, OR and WITH.
  /// Throws [FormatException] on invalid syntax or unregistered SPDX IDs.
  factory LicenseExpression.parse(String text) => _Parser(text).parse();

  /// Leaf license terms, including WITH exceptions as whole terms.
  Set<String> get terms;
}

/// One SPDX license, optionally qualified by an SPDX exception.
final class LicenseTerm extends LicenseExpression {
  /// Validates a single SPDX term using the expression parser.
  factory LicenseTerm(String value) {
    final expression = LicenseExpression.parse(value);
    if (expression is! LicenseTerm) {
      throw FormatException('Expected one SPDX license term: $value');
    }
    return expression;
  }
  const LicenseTerm._(this.id, this.exception);

  /// Canonical SPDX identifier (or an explicit LicenseRef).
  final String id;

  /// Canonical exception ID, if present.
  final String? exception;
  @override
  Set<String> get terms => Set.unmodifiable({toString()});
  @override
  String toString() => exception == null ? id : '$id WITH $exception';
}

/// All components must be permitted by the policy.
final class LicenseAnd extends LicenseExpression {
  /// Combines two required expressions.
  const LicenseAnd(this.left, this.right);

  /// Left component.
  final LicenseExpression left;

  /// Right component.
  final LicenseExpression right;
  @override
  Set<String> get terms => Set.unmodifiable({...left.terms, ...right.terms});
  @override
  String toString() => '($left AND $right)';
}

/// Any one permitted alternative satisfies the policy.
final class LicenseOr extends LicenseExpression {
  /// Combines two alternative expressions.
  const LicenseOr(this.left, this.right);

  /// Left alternative.
  final LicenseExpression left;

  /// Right alternative.
  final LicenseExpression right;
  @override
  Set<String> get terms => Set.unmodifiable({...left.terms, ...right.terms});
  @override
  String toString() => '($left OR $right)';
}

final class _Parser {
  _Parser(String text)
    : tokens = RegExp(r'\(|\)|[^\s()]+')
          .allMatches(text)
          .map((m) => m.group(0)!)
          .toList();
  final List<String> tokens;
  int index = 0;
  LicenseExpression parse() {
    if (tokens.length > 512) {
      throw const FormatException('SPDX expression too long');
    }
    final result = _or();
    if (index != tokens.length) _fail();
    return result;
  }

  bool _take(String token) {
    if (index < tokens.length && tokens[index] == token) {
      index++;
      return true;
    }
    return false;
  }

  Never _fail() =>
      throw FormatException('Invalid SPDX expression near token ${index + 1}');
  LicenseExpression _or() {
    var value = _and();
    while (_take('OR')) {
      value = LicenseOr(value, _and());
    }
    return value;
  }

  LicenseExpression _and() {
    var value = _primary();
    while (_take('AND')) {
      value = LicenseAnd(value, _primary());
    }
    return value;
  }

  LicenseExpression _primary() {
    if (_take('(')) {
      final value = _or();
      if (!_take(')')) _fail();
      return value;
    }
    if (index >= tokens.length) _fail();
    var id = tokens[index++];
    // Legacy SPDX plus notation maps to the canonical or-later identifier.
    if (id.endsWith('+')) {
      id = '${id.substring(0, id.length - 1)}-or-later';
    }
    if (!spdxLicenseIds.contains(id) &&
        !RegExp(r'^(DocumentRef-[A-Za-z0-9.-]+:)?LicenseRef-[A-Za-z0-9.-]+$')
            .hasMatch(id)) {
      throw FormatException('Unknown SPDX identifier "$id"');
    }
    String? exception;
    if (_take('WITH')) {
      if (index >= tokens.length) _fail();
      exception = tokens[index++];
      if (!spdxExceptionIds.contains(exception)) {
        throw FormatException('Unknown SPDX exception "$exception"');
      }
    }
    return LicenseTerm._(id, exception);
  }
}
