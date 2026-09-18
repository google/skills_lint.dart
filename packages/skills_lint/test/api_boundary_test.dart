// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_lint/skills_lint.dart';
import 'package:test/test.dart';

/// Validates that the public library (`package:skills_lint/skills_lint.dart`)
/// exposes everything needed for programmatic use without internal `src/` imports.
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

    test('Configuration round-trips through YAML using only the public API', () {
      const config = Configuration(
        ruleConfigs: {'check-relative-paths': RuleConfigPatch(severity: AnalysisSeverity.error)},
      );

      final String yamlString = config.toYamlString();
      final Configuration parsed = ConfigParser.parse(yamlString);
      expect(parsed.toYamlString(), equals(config.toYamlString()));
    });

    test('validateSkills throws MissingDefaultsException a caller can catch by name', () async {
      // The `on MissingDefaultsException` clause below only compiles while the
      // type is reachable from the public library. Dropping the export turns
      // this into an analysis error rather than a silent regression, which is
      // the point of the test: a caller must be able to name what it catches.
      final Directory emptyDir = await Directory.systemTemp.createTemp('skills_lint_no_defaults.');
      addTearDown(() async {
        if (emptyDir.existsSync()) {
          await emptyDir.delete(recursive: true);
        }
      });

      Future<bool> validateWithNoTargets() => IOOverrides.runZoned(
        () => validateSkills(quiet: true),
        getCurrentDirectory: () => emptyDir,
      );

      await expectLater(validateWithNoTargets(), throwsA(isA<MissingDefaultsException>()));

      List<String>? reportedDefaults;
      try {
        await validateWithNoTargets();
      } on MissingDefaultsException catch (e) {
        reportedDefaults = e.defaults;
      }

      expect(reportedDefaults, containsAll(['.claude/skills', '.agents/skills']));
    });
  });
}
