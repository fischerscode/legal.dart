import 'dart:io';

import 'package:path/path.dart' as p;

import 'config/config.dart';
import 'dependencies/scanner.dart';
import 'licenses/detector.dart';
import 'licenses/runtime_bundle.dart';
import 'model/models.dart';
import 'rendering/report.dart';

/// A resolved Dart project and its immutable license settings.
final class LegalProject {
  LegalProject._(
    this.directory,
    this.config,
    this.scanner,
    this.detector,
    this.runtimeLicenseCatalog,
  );

  /// Absolute project directory.
  final Directory directory;

  /// Typed policy and default output options.
  final LegalConfig config;

  /// Dependency discovery strategy and SDK executable.
  final DependencyScanner scanner;

  /// Local document recognition strategy.
  final LicenseDetector detector;

  /// Optional injected offline runtime catalog; defaults to the bundled catalog.
  final RuntimeLicenseCatalog? runtimeLicenseCatalog;

  /// Loads project configuration; no scan, network access, or writes occur.
  static Future<LegalProject> load(
    String path, {
    String? configPath,
    DependencyScanner scanner = const DependencyScanner(),
    LicenseDetector detector = const LicenseDetector(),
    RuntimeLicenseCatalog? runtimeLicenseCatalog,
  }) async {
    final directory = Directory(p.normalize(p.absolute(path)));
    if (!await File(p.join(directory.path, 'pubspec.yaml')).exists()) {
      throw const LegalException(
        'Could not find pubspec.yaml. Run from a Dart package or specify --project.',
      );
    }
    try {
      return LegalProject._(
        directory,
        await LegalConfig.load(directory, configPath: configPath),
        scanner,
        detector,
        runtimeLicenseCatalog,
      );
    } on FileSystemException catch (error) {
      throw LegalException(
        'Could not load configuration: ${error.message} (${error.path})',
      );
    }
  }

  /// Inventories resolved dependencies, excluding the selected project itself.
  /// [includeSdk] adds SDK evidence; [sdkPath] selects the build SDK directory.
  /// Without an explicit path, source execution uses the running Dart SDK.
  /// [sdkTarget] selects the runtime bundle target, defaulting to the host ABI.
  /// [sdkLicenseFiles] replaces configured additional paths, relative to the SDK.
  /// Ignores are applied during checks/rendering, not during graph traversal.
  Future<LicenseReport> scan({
    bool? includeDev,
    bool? includeSdk,
    String? sdkPath,
    String? sdkTarget,
    Iterable<String>? sdkLicenseFiles,
  }) async {
    try {
      final dependencies = await scanner.scan(
        directory,
        includeDev: includeDev ?? config.includeDev,
      );
      final packages = <PackageLicense>[];
      for (final dependency in dependencies) {
        packages.add(await detector.detect(dependency));
      }
      RuntimeLicenseCoverage? coverage;
      if (includeSdk ?? config.includeSdk) {
        final selectedPath = sdkPath ?? config.sdkPath;
        final Directory sdk;
        if (selectedPath != null) {
          sdk = Directory(
            p.isAbsolute(selectedPath)
                ? selectedPath
                : p.join(directory.path, selectedPath),
          );
        } else {
          final executable = File(Platform.resolvedExecutable);
          final name = p.basename(executable.path).toLowerCase();
          if (name != 'dart' && name != 'dart.exe') {
            throw const LegalException(
              'Cannot discover the build SDK from a compiled executable. '
              'Specify --sdk-path or legal.sdk_path.',
            );
          }
          sdk = executable.parent.parent;
        }
        final sdkLicense = await detector.detectSdk(
          sdk,
          additionalFiles: sdkLicenseFiles ?? config.sdkLicenseFiles,
        );
        packages.add(sdkLicense);
        final target =
            sdkTarget ?? config.sdkTarget ?? RuntimeLicenseCatalog.hostTarget;
        if (!RegExp(r'^[a-z0-9]+-[a-z0-9]+$').hasMatch(target)) {
          throw const LegalException(
            'Invalid SDK target: expected OS-architecture, such as linux-x64.',
          );
        }
        final bundle = (runtimeLicenseCatalog ?? RuntimeLicenseCatalog.bundled)
            .find(sdkLicense.dependency.version, target);
        coverage = RuntimeLicenseCoverage(
          sdkVersion: sdkLicense.dependency.version,
          target: target,
          bundleId: bundle == null ? null : 'dart-${bundle.sdkVersion}-$target',
          issues:
              bundle?.coverageIssues ??
              [
                'No native runtime license bundle for Dart ${sdkLicense.dependency.version} / $target. '
                    'Installed SDK documents and additional files do not establish complete native runtime coverage.',
              ],
        );
        if (bundle != null) {
          packages.addAll(
            bundle.components.map(
              (component) => component.inventory(sdkLicense.dependency),
            ),
          );
        }
      }
      return LicenseReport(packages, runtimeCoverage: coverage);
    } on FileSystemException catch (error) {
      throw LegalException(
        'Could not read license evidence: ${error.message} (${error.path}). Run dart pub get and check file permissions.',
      );
    } on FormatException catch (error) {
      throw LegalException(
        'Could not decode project or license data: ${error.message}',
      );
    }
  }
}
