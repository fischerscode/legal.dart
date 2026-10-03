import 'dart:io';

import 'package:legal/legal.dart';
import 'package:legal/src/licenses/reference_texts.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  const detector = LicenseDetector();
  late Directory directory;
  late Dependency dependency;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('legal-license-');
    await File(p.join(directory.path, 'pubspec.yaml'))
        .writeAsString('name: sample\nversion: 1.0.0\n');
    dependency = Dependency(
      name: 'sample',
      version: '1.0.0',
      root: directory.uri,
      source: 'path',
      direct: true,
    );
  });
  tearDown(() => directory.delete(recursive: true));
  for (final filename in [
    'LICENSE',
    'LICENSE.txt',
    'LICENSE.md',
    'LICENCE',
    'COPYING',
    'license',
    'LICENSE-MIT',
  ]) {
    test('detects $filename and preserves full original text', () async {
      final text = referenceTexts['MIT']!;
      await File(p.join(directory.path, filename)).writeAsString(text);
      final result = await detector.detect(dependency);
      expect(result.expression.toString(), 'MIT');
      expect(result.documents.single.text, text);
      expect(result.documents.single.path, filename);
      expect(result.requiresReview, isFalse);
    });
  }
  for (final entry in referenceTexts.entries) {
    test('full reference detection ${entry.key}', () {
      expect(
        detector.identify(entry.value).toString(),
        entry.key == 'BSD-3-Clause-dart' ? 'BSD-3-Clause' : entry.key,
      );
      expect(
        detector.identify('${entry.value}\nYou must pay us royalties.'),
        isNull,
      );
    });
  }
  test('copyright-prefixed extra terms cannot be normalized away', () {
    expect(
      detector.identify(
        '${referenceTexts['MIT']}\nCopyright law requires you to pay a royalty.',
      ),
      isNull,
    );
  });
  test('an SPDX-only document remains incomplete', () async {
    await File(p.join(directory.path, 'LICENSE'))
        .writeAsString('SPDX-License-Identifier: MIT\n');
    expect((await detector.detect(dependency)).requiresReview, isTrue);
  });
  test('a comment-wrapped SPDX-only document remains incomplete', () async {
    await File(p.join(directory.path, 'LICENSE'))
        .writeAsString('/* SPDX-License-Identifier: MIT */\n');
    final result = await detector.detect(dependency);
    expect(result.expression.toString(), 'MIT');
    expect(result.requiresReview, isTrue);
  });
  test('NOTICE survives and never becomes a license term', () async {
    await File(p.join(directory.path, 'LICENSE'))
        .writeAsString(referenceTexts['Apache-2.0']!);
    const notice = 'Attribution\r\nCopyright ACME\r\n';
    await File(p.join(directory.path, 'NOTICE')).writeAsString(notice);
    final result = await detector.detect(dependency);
    expect(result.expression.toString(), 'Apache-2.0');
    expect(result.documents.last.text, notice);
    expect(result.documents.last.kind, LicenseDocumentKind.notice);
  });
  test('multiple license files require all terms, no guessed OR', () async {
    await File(p.join(directory.path, 'LICENSE-MIT'))
        .writeAsString(referenceTexts['MIT']!);
    await File(p.join(directory.path, 'COPYING'))
        .writeAsString(referenceTexts['BSD-2-Clause']!);
    final result = await detector.detect(dependency);
    expect(result.expression, isA<LicenseAnd>());
    expect(result.expression!.terms, {'MIT', 'BSD-2-Clause'});
    expect(result.documents.length, 2);
  });
  test(
    'unknown extra file still requires review alongside known license',
    () async {
      await File(p.join(directory.path, 'LICENSE'))
          .writeAsString(referenceTexts['MIT']!);
      await File(p.join(directory.path, 'COPYING'))
          .writeAsString('Proprietary conditions');
      final result = await detector.detect(dependency);
      expect(result.expression.toString(), 'MIT');
      expect(result.requiresReview, isTrue);
    },
  );
  test('empty file and missing license are review findings', () async {
    expect((await detector.detect(dependency)).requiresReview, isTrue);
    await File(p.join(directory.path, 'LICENSE')).writeAsString('');
    expect(
      (await detector.detect(dependency)).issues,
      contains('LICENSE is empty'),
    );
  });
  test('invalid UTF8 is a scan error, not guessed evidence', () async {
    await File(p.join(directory.path, 'LICENSE'))
        .writeAsBytes([0xff, 0xfe, 0xff]);
    expect(
      () => detector.detect(dependency),
      throwsA(isA<FileSystemException>()),
    );
  });
  test(
    'metadata records a declaration but cannot replace absent original terms',
    () async {
      await File(p.join(directory.path, 'pubspec.yaml'))
          .writeAsString('name: sample\nlicense: MIT\n');
      final result = await detector.detect(dependency);
      expect(result.expression.toString(), 'MIT');
      expect(result.metadataExpression.toString(), 'MIT');
      expect(result.requiresReview, isTrue);
    },
  );
  test('REUSE LICENSES directory', () async {
    await Directory(p.join(directory.path, 'LICENSES')).create();
    await File(p.join(directory.path, 'LICENSES', 'MIT.txt'))
        .writeAsString(referenceTexts['MIT']!);
    expect(
      (await detector.detect(dependency)).documents.single.path,
      'LICENSES/MIT.txt',
    );
  });
  test('SPDX declarations and expressions, no keyword guessing', () {
    expect(
      detector
          .identify(
            'SPDX-License-Identifier: MIT OR Apache-2.0\nDeclared license text',
          )
          .toString(),
      '(MIT OR Apache-2.0)',
    );
    expect(
      detector
          .identify('# SPDX-License-Identifier: GPL-3.0-only\nTerms')
          .toString(),
      'GPL-3.0-only',
    );
    expect(detector.identify('This project mentions MIT and Apache'), isNull);
    expect(detector.identify('SPDX-License-Identifier: MADE-UP'), isNull);
    expect(
      detector.identify(
        'SPDX-License-Identifier: MIT\nSPDX-License-Identifier: GPL-3.0-only',
      ),
      isNull,
    );
  });
}
