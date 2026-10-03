import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../../legal.dart';

/// CommandRunner adapter with injected output; domain code never writes stdout.
final class LegalCommandRunner extends CommandRunner<int> {
  /// Creates list, check and generate commands; streams default to the terminal.
  LegalCommandRunner({StringSink? output})
    : super(
        'legal',
        'Inventory dependency licenses and evaluate project policy.',
      ) {
    final sink = output ?? stdout;
    for (final action in _Action.values) {
      addCommand(_LegalCommand(action, sink));
    }
  }
}

enum _Action { list, check, generate }

final class _Options {
  _Options(ArgResults args)
    : project = args.option('project')!,
      config = args.option('config'),
      includeDev = args.wasParsed('include-dev')
          ? args.flag('include-dev')
          : null,
      output = args.option('output'),
      json = args.flag('json'),
      allowIncomplete = args.flag('allow-incomplete');
  final String project;
  final String? config;
  final bool? includeDev;
  final String? output;
  final bool json;
  final bool allowIncomplete;
}

final class _LegalCommand extends Command<int> {
  _LegalCommand(this.action, this.output) {
    argParser
      ..addOption('project', defaultsTo: '.', help: 'Dart project directory.')
      ..addOption(
        'config',
        help: 'Explicit policy YAML file, relative to the project.',
      )
      ..addFlag(
        'include-dev',
        defaultsTo: false,
        help: 'Include the project’s dev dependency closure.',
      )
      ..addOption(
        'output',
        abbr: 'o',
        help: 'Generated notice file (generate only).',
      )
      ..addFlag(
        'json',
        negatable: false,
        help: 'JSON inventory and findings (list/check only).',
      )
      ..addFlag(
        'allow-incomplete',
        negatable: false,
        help: 'Permit an explicitly marked draft (generate only).',
      );
  }
  final _Action action;
  final StringSink output;
  @override
  String get name => action.name;
  @override
  String get description => switch (action) {
    _Action.list => 'List resolved dependencies and license evidence.',
    _Action.check => 'Check dependency licenses against the project policy.',
    _Action.generate => 'Generate a deterministic THIRD_PARTY_LICENSES.txt.',
  };
  @override
  Future<int> run() async {
    final args = argResults!;
    if (args.rest.isNotEmpty) {
      usageException('Unexpected positional arguments: ${args.rest.join(' ')}');
    }
    final options = _Options(args);
    if (action == _Action.generate && options.json) {
      usageException('--json is available for list and check.');
    }
    if (action != _Action.generate &&
        (options.output != null || options.allowIncomplete)) {
      usageException(
        '--output and --allow-incomplete are available for generate.',
      );
    }
    final project = await LegalProject.load(
      options.project,
      configPath: options.config,
    );
    final report = await project.scan(includeDev: options.includeDev);
    final result = report.check(project.config.policy);
    if (action == _Action.generate) {
      final text = report.renderThirdPartyLicenses(
        policy: project.config.policy,
        allowIncomplete: options.allowIncomplete,
      );
      final file = File(
        p.isAbsolute(options.output ?? project.config.output)
            ? options.output ?? project.config.output
            : p.join(
                project.directory.path,
                options.output ?? project.config.output,
              ),
      );
      // Guard original evidence and project inputs against accidental overwrite.
      final target = p.normalize(p.absolute(file.path));
      final protected = <String>{
        p.join(project.directory.path, 'pubspec.yaml'),
        p.join(project.directory.path, 'pubspec.lock'),
        if (options.config != null)
          p.join(project.directory.path, options.config!),
        for (final package in report.packages)
          for (final doc in package.documents)
            p.join(Directory.fromUri(package.dependency.root).path, doc.path),
      };
      if (protected.map((s) => p.normalize(p.absolute(s))).contains(target) ||
          await Link(target).exists()) {
        throw LegalException(
          'Refusing to overwrite project inputs, license evidence, or a symbolic link: $target',
        );
      }
      await file.parent.create(recursive: true);
      final temp = await Directory.systemTemp.createTemp('legal-output-');
      // Stage in the destination directory so rename is atomic on its filesystem.
      final staging = File(
        p.join(file.parent.path, '.legal-${p.basename(temp.path)}.tmp'),
      );
      try {
        await staging.writeAsString(text, flush: true);
        await staging.rename(file.path);
      } finally {
        if (await staging.exists()) await staging.delete();
        await temp.delete();
      }
      output.writeln(
        'Generated ${file.path}${options.allowIncomplete ? ' (drafts permitted)' : ''}',
      );
      return 0;
    }
    if (options.json) {
      output.writeln(report.toJson(policy: project.config.policy));
    } else {
      for (final finding in result.findings) {
        final package = finding.package;
        final symbol = switch (finding.status) {
          LicenseStatus.allowed => '✓',
          LicenseStatus.denied => '✗',
          LicenseStatus.requiresReview => '?',
          LicenseStatus.ignored => '-',
        };
        output.writeln(
          '$symbol ${package.dependency.name} ${package.dependency.version} '
          '${package.expression ?? 'unknown'} — ${finding.message}',
        );
      }
      output.writeln(
        '${report.packages.length} dependencies; policy ${result.isSuccess ? 'satisfied' : 'requires action'}.',
      );
    }
    return action == _Action.check && !result.isSuccess ? 1 : 0;
  }
}

/// Runs the CLI with documented exit codes and concise expected-error messages.
Future<int> runLegal(
  List<String> arguments, {
  StringSink? output,
  StringSink? errors,
}) async {
  final errorSink = errors ?? stderr;
  final verbose = arguments.contains('--verbose');
  final filtered = arguments.where((arg) => arg != '--verbose').toList();
  try {
    return await LegalCommandRunner(output: output).run(filtered) ?? 0;
  } on UsageException catch (error) {
    errorSink.writeln(error);
    return 64;
  } on LegalException catch (error) {
    errorSink.writeln(error.message);
    return 2;
  } on FileSystemException catch (error) {
    errorSink.writeln(
      'File operation failed: ${error.message} (${error.path})',
    );
    return 2;
  } catch (error, stack) {
    errorSink.writeln('Unexpected error: $error');
    if (verbose) errorSink.writeln(stack);
    return 2;
  }
}
