import 'dart:io';

import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';

void main(List<String> arguments) {
  if (arguments.length != 1) {
    stderr.writeln('Usage: dart run tool/validate_release.dart v<version>');
    exitCode = 64;
    return;
  }
  final document = loadYaml(File('pubspec.yaml').readAsStringSync()) as YamlMap;
  final version = document['version'] as String;
  final parsed = Version.parse(version);
  if (arguments.single != 'v$version' ||
      parsed.toString() != version ||
      parsed.build.isNotEmpty) {
    stderr.writeln(
      'Release tag must exactly equal v$version (no build metadata). Got ${arguments.single}.',
    );
    exitCode = 1;
    return;
  }
  stdout.writeln('Verified legal $version and tag ${arguments.single}.');
}
