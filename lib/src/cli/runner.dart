import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../../legal.dart';

/// CommandRunner adapter with injected output; domain code never writes stdout.
final class LegalCommandRunner extends CommandRunner<int> {
  /// Creates commands with optional output and overwrite confirmation adapters.
  /// By default, confirmation requires a terminal and accepts `y` or `yes`.
  LegalCommandRunner({
    StringSink? output,
    Future<bool> Function(String path)? confirmOverwrite,
  }) : super(
         'legal',
         'Inventory dependency licenses and evaluate project policy.',
       ) {
    final sink = output ?? stdout;
    for (final action in _Action.values) {
      addCommand(
        _LegalCommand(
          action,
          sink,
          confirmOverwrite ?? (path) => _confirmOverwrite(path, stderr),
        ),
      );
    }
  }
}

enum _Action { list, check, generate }

final class _Options {
  _Options(ArgResults args)
    : project = args.option('project')!,
      config = args.option('config'),
      sdkPath = args.option('sdk-path'),
      sdkTarget = args.option('sdk-target'),
      sdkLicenseFiles = args.wasParsed('sdk-license-file')
          ? args.multiOption('sdk-license-file')
          : null,
      includeSdk = args.wasParsed('include-sdk')
          ? args.flag('include-sdk')
          : null,
      licenseDataDirectory = args.option('license-data'),
      includeDev = args.wasParsed('include-dev')
          ? args.flag('include-dev')
          : null,
      output = args.option('output'),
      json = args.flag('json'),
      allowIncomplete = args.flag('allow-incomplete'),
      force = args.flag('force');
  final String project;
  final String? config;
  final String? sdkPath;
  final String? sdkTarget;
  final List<String>? sdkLicenseFiles;
  final bool? includeSdk;
  final String? licenseDataDirectory;
  final bool? includeDev;
  final String? output;
  final bool json;
  final bool allowIncomplete;
  final bool force;
}

final class _LegalCommand extends Command<int> {
  _LegalCommand(this.action, this.output, this.confirmOverwrite) {
    argParser
      ..addOption('project', defaultsTo: '.', help: 'Dart project directory.')
      ..addOption(
        'license-data',
        help: 'pana SPDX corpus directory, relative to the project (required for AOT).',
      )
      ..addOption(
        'config',
        help: 'Explicit policy YAML file, relative to the project.',
      )
      ..addFlag(
        'include-dev',
        defaultsTo: false,
        help: 'Include the project’s dev dependency closure.',
      )
      ..addFlag(
        'include-sdk',
        defaultsTo: false,
        help: 'Include Dart SDK license evidence in inventory, checks and notices.',
      )
      ..addOption(
        'sdk-path',
        help: 'Build Dart SDK directory, relative to the project or absolute.',
      )
      ..addOption(
        'sdk-target',
        help:
            'Runtime bundle target OS-architecture (defaults to the host ABI).',
      )
      ..addMultiOption(
        'sdk-license-file',
        splitCommas: false,
        help: 'Additional runtime license/notice file, relative to the SDK or absolute (repeatable).',
      )
      ..addOption(
        'output',
        abbr: 'o',
        help: 'Generated notice file (generate only).',
      )
      ..addFlag(
        'force',
        negatable: false,
        help: 'Overwrite an existing output without asking (generate only).',
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
  final Future<bool> Function(String path) confirmOverwrite;
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
        (options.output != null || options.allowIncomplete || options.force)) {
      usageException(
        '--output, --allow-incomplete and --force are available for generate.',
      );
    }
    final project = await LegalProject.load(
      options.project,
      configPath: options.config,
      detector: LicenseDetector(
        licenseDataDirectory: options.licenseDataDirectory == null
            ? null
            : p.join(options.project, options.licenseDataDirectory!),
      ),
    );
    final report = await project.scan(
      includeDev: options.includeDev,
      includeSdk: options.includeSdk,
      sdkPath: options.sdkPath,
      sdkTarget: options.sdkTarget,
      sdkLicenseFiles: options.sdkLicenseFiles,
    );
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
      final type = await FileSystemEntity.type(file.path, followLinks: false);
      if (type != FileSystemEntityType.notFound &&
          !options.force &&
          !await confirmOverwrite(file.path)) {
        throw LegalException('Output was not overwritten: ${file.path}');
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
      for (final issue in result.issues) {
        output.writeln('INCOMPLETE SDK RUNTIME COVERAGE: $issue');
      }
      output.writeln(
        '${report.packages.length} dependencies; policy ${result.isSuccess ? 'satisfied' : 'requires action'}.',
      );
    }
    return action == _Action.check && !result.isSuccess ? 1 : 0;
  }
}

Future<bool> _confirmOverwrite(String path, StringSink prompt) async {
  if (!stdin.hasTerminal || !stdout.hasTerminal) {
    throw LegalException(
      'Output already exists: $path. Use --force to overwrite it in non-interactive mode.',
    );
  }
  prompt.write('Overwrite "$path"? [y/N] ');
  final answer = stdin.readLineSync()?.trim().toLowerCase();
  return answer == 'y' || answer == 'yes';
}

/// Runs the CLI with documented exit codes and concise expected-error messages.
/// [confirmOverwrite] replaces the terminal prompt for an existing output.
Future<int> runLegal(
  List<String> arguments, {
  StringSink? output,
  StringSink? errors,
  Future<bool> Function(String path)? confirmOverwrite,
}) async {
  final errorSink = errors ?? stderr;
  final verbose = arguments.contains('--verbose');
  final filtered = arguments.where((arg) => arg != '--verbose').toList();
  try {
    return await LegalCommandRunner(
          output: output,
          confirmOverwrite:
              confirmOverwrite ?? (path) => _confirmOverwrite(path, errorSink),
        ).run(filtered) ??
        0;
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
