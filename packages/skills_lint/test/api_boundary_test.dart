// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_lint/skills_lint.dart';
import 'package:test/test.dart';

/// Validates the public API contract exposed by `package:skills_lint/skills_lint.dart`.
///
/// This test ensures that consumers can embed and execute the linter programmatically
/// without needing internal implementation imports (`package:skills_lint/src/...`),
/// guarding against accidental API leakage or missing public exports.
///
/// Originally introduced as `example/api_boundary_runner` (see
/// https://github.com/flutter/agent-plugins/pull/183), this test exercises the
/// public API boundary with `implementation_imports` enforced by static analysis.
void main() {
  group('Public API boundary validation', () {
    late String validSkillPath;
    late String invalidSkillPath;

    setUpAll(() {
      validSkillPath = p.normalize(p.absolute(p.join('example', 'skills', 'valid')));
      invalidSkillPath = p.normalize(p.absolute(p.join('example', 'skills', 'invalid')));
      expect(Directory(validSkillPath).existsSync(), isTrue);
      expect(Directory(invalidSkillPath).existsSync(), isTrue);
    });

    test('validateSkills accepts individualSkillPaths and rule overrides', () async {
      final bool validResult = await validateSkills(
        individualSkillPaths: [validSkillPath],
        resolvedRuleConfigs: {
          'check-absolute-paths': const RuleConfigPatch(severity: AnalysisSeverity.disabled),
        },
      );
      expect(validResult, isTrue);
    });

    test('validateSkills detects errors in invalid fixture', () async {
      final bool invalidResult = await validateSkills(
        individualSkillPaths: [invalidSkillPath],
        printWarnings: false,
        quiet: true,
      );
      expect(invalidResult, isFalse);
    });

    test('Validator class provides structured results', () async {
      final validator = Validator();
      final ValidationResult result = await validator.validate(Directory(validSkillPath));
      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
    });
  });
}
