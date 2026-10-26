// Copy this file to test/skills_lint_test.dart in your package.

import 'package:skills_lint/skills_lint.dart';
import 'package:test/test.dart';

void main() {
  test('skills pass skills_lint', () async {
    final Configuration config = await ConfigParser.loadConfig();
    expect(
      config.directoryConfigs,
      isNotEmpty,
      reason: 'skills_lint.yaml must list at least one skills directory.',
    );

    final bool passed = await validateSkills(config: config);

    expect(passed, isTrue, reason: 'skills_lint found errors. Its findings are printed above.');
  });
}
