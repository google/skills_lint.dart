// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// ignore_for_file: avoid_print

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_lint/skills_lint.dart';

Future<void> main() async {
  // 1. Path to the skill directory containing SKILL.md
  final String validSkillPath = p.join('example', 'skills', 'valid');

  print('=== 1. High-Level Validation API ===');
  // Use `validateSkills` for quick CLI-like validation runs:
  final bool isValid = await validateSkills(individualSkillPaths: [validSkillPath]);
  print('Skill validation passed: $isValid\n');

  print('=== 2. Programmatic Validator API ===');
  // Use `Validator` for detailed, structured inspection of errors/warnings:
  final validator = Validator(
    ruleConfigs: {
      // You can customize rule severities programmatically:
      'invalid-skill-name': RuleConfig(severity: AnalysisSeverity.error),
      'check-trailing-whitespace': RuleConfig(severity: AnalysisSeverity.warning),
    },
  );

  final skillDir = Directory(validSkillPath);
  final ValidationResult result = await validator.validate(skillDir);

  if (result.isValid) {
    print('Skill at "${skillDir.path}" is valid!');
  } else {
    print('Found ${result.validationErrors.length} violation(s):');
    for (final ValidationError error in result.validationErrors) {
      print('  [${error.ruleId}] ${error.message} (${error.file})');
    }
  }
}
