import 'dart:io';

import 'package:legal/src/cli/runner.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await runLegal(arguments);
}
