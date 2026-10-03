import 'package:legal/legal.dart';

Future<void> main() async {
  final project = await LegalProject.load('.');
  final report = await project.scan();
  final result = report.check(project.config.policy);
  print('Policy satisfied: ${result.isSuccess}');
  print(report.renderThirdPartyLicenses(policy: project.config.policy));
}
