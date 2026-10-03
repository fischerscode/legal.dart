import 'dart:io';

Future<void> main() async {
  final commands = <List<String>>[
    ['format', '--output=none', '--set-exit-if-changed', '.'],
    ['analyze', '--fatal-infos'],
    ['test'],
    ['run', 'legal', 'check'],
    ['pub', 'publish', '--dry-run'],
  ];
  for (final arguments in commands) {
    stdout.writeln('dart ${arguments.join(' ')}');
    final process = await Process.start(
      Platform.resolvedExecutable,
      arguments,
      mode: ProcessStartMode.inheritStdio,
    );
    final code = await process.exitCode;
    if (code != 0) {
      exitCode = code;
      return;
    }
  }
}
