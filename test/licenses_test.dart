import 'dart:io';
import 'dart:isolate';

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
    test('pana reference detection ${entry.key}', () async {
      expect(
        (await detector.identify(entry.value)).toString(),
        entry.key == 'BSD-3-Clause-dart' ? 'BSD-3-Clause' : entry.key,
      );
      await File(p.join(directory.path, 'LICENSE')).writeAsString(entry.value);
      expect((await detector.detect(dependency)).requiresReview, isFalse);
      await File(p.join(directory.path, 'LICENSE'))
          .writeAsString('${entry.value}\nYou must pay us royalties.');
      final modified = await detector.detect(dependency);
      expect(modified.requiresReview, isTrue);
      expect(modified.expression, isNotNull);
    });
  }
  for (final id in ['MPL-2.0', 'CC0-1.0']) {
    test(
      'recognizes $id from pana beyond the previous reference subset',
      () async {
        final uri = await Isolate.resolvePackageUri(
          Uri.parse('package:pana/src/third_party/spdx/licenses/$id.txt'),
        );
        final text = await File.fromUri(uri!).readAsString();
        await File(p.join(directory.path, 'LICENSE')).writeAsString(text);
        final result = await detector.detect(dependency);
        expect(result.expression.toString(), id);
        expect(result.requiresReview, isFalse);
        expect(result.documents.single.text, text);
        expect(
          LicenseReport([result]).check(LicensePolicy(allow: {id})).isSuccess,
          isTrue,
        );
      },
    );
  }
  test(
    'multiple texts in one document retain all terms without guessed OR',
    () async {
      await File(p.join(directory.path, 'LICENSE')).writeAsString(
        '${referenceTexts['MIT']}\n===\n${referenceTexts['BSD-2-Clause']}',
      );
      final result = await detector.detect(dependency);
      expect(result.expression!.terms, {'MIT', 'BSD-2-Clause'});
      expect(result.requiresReview, isFalse);
    },
  );
  test(
    'recognized changed terms retain candidate and require review',
    () async {
      final text = referenceTexts['Apache-2.0']!.replaceFirst(
        'royalty-free',
        'royalty-bearing',
      );
      await File(p.join(directory.path, 'LICENSE')).writeAsString(text);
      final result = await detector.detect(dependency);
      expect(result.expression.toString(), 'Apache-2.0');
      expect(result.requiresReview, isTrue);
      expect(result.issues.join(' '), contains('changed text'));
      expect(
        LicenseReport([result]).check(LicensePolicy.permissive()).isSuccess,
        isFalse,
      );
      expect(result.documents.single.text, text);
    },
  );
  test('copyright-prefixed extra terms remain review findings', () async {
    await File(p.join(directory.path, 'LICENSE')).writeAsString(
      '${referenceTexts['MIT']}\nCopyright law requires you to pay a royalty.',
    );
    expect((await detector.detect(dependency)).requiresReview, isTrue);
  });
  test('empty, truncated and wholly unknown input is not guessed', () async {
    expect(await detector.identify(''), isNull);
    expect(await detector.identify('Proprietary conditions'), isNull);
    expect(
      await detector.identify(referenceTexts['MIT']!.substring(0, 50)),
      isNull,
    );
  });
  test('MIT title and copyright formatting are accepted', () async {
    await File(p.join(directory.path, 'LICENSE')).writeAsString(
      'MIT License\nCopyright (c) 2026 Example authors\n${referenceTexts['MIT']}',
    );
    expect((await detector.detect(dependency)).requiresReview, isFalse);
  });
  test('a long unknown suffix is not accepted as a clean match', () async {
    await File(p.join(directory.path, 'LICENSE')).writeAsString(
      '${referenceTexts['MIT']}\n${List.filled(60, 'obligation').join(' ')}',
    );
    expect((await detector.detect(dependency)).requiresReview, isTrue);
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
  test('SPDX declarations and expressions, no keyword guessing', () async {
    expect(
      (await detector.identify(
        'SPDX-License-Identifier: MIT OR Apache-2.0\nDeclared license text',
      )).toString(),
      '(MIT OR Apache-2.0)',
    );
    expect(
      (await detector.identify(
        '# SPDX-License-Identifier: GPL-3.0-only\nTerms',
      )).toString(),
      'GPL-3.0-only',
    );
    expect(
      await detector.identify('This project mentions MIT and Apache'),
      isNull,
    );
    expect(await detector.identify('SPDX-License-Identifier: MADE-UP'), isNull);
    expect(
      await detector.identify(
        'SPDX-License-Identifier: MIT\nSPDX-License-Identifier: GPL-3.0-only',
      ),
      isNull,
    );
  });
}
