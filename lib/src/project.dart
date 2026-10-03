import 'dart:io';

import 'package:path/path.dart' as p;

import 'config/config.dart';
import 'dependencies/scanner.dart';
import 'licenses/detector.dart';
import 'model/models.dart';
import 'rendering/report.dart';

/// A resolved Dart project and its immutable license settings.
final class LegalProject {
  LegalProject._(this.directory, this.config, this.scanner, this.detector);

  /// Absolute project directory.
  final Directory directory;

  /// Typed policy and default output options.
  final LegalConfig config;

  /// Dependency discovery strategy and SDK executable.
  final DependencyScanner scanner;

  /// Local document recognition strategy.
  final LicenseDetector detector;

  /// Loads project configuration; no scan, network access, or writes occur.
  static Future<LegalProject> load(
    String path, {
    String? configPath,
    DependencyScanner scanner = const DependencyScanner(),
    LicenseDetector detector = const LicenseDetector(),
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
      );
    } on FileSystemException catch (error) {
      throw LegalException(
        'Could not load configuration: ${error.message} (${error.path})',
      );
    }
  }

  /// Inventories resolved dependencies, excluding the selected project itself.
  /// Ignores are applied during checks/rendering, not during graph traversal.
  Future<LicenseReport> scan({bool? includeDev}) async {
    try {
      final dependencies = await scanner.scan(
        directory,
        includeDev: includeDev ?? config.includeDev,
      );
      final packages = <PackageLicense>[];
      for (final dependency in dependencies) {
        packages.add(await detector.detect(dependency));
      }
      return LicenseReport(packages);
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
