// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:skills_lint/skills_lint.dart';
import 'package:skills_lint/src/models/check_type.dart';
import 'package:skills_lint/src/rule_registry.dart';
import 'package:skills_lint/src/unknown_rule_names.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  group('configurableRuleNames', () {
    test('includes built-in checks and skill-file-inaccessible', () {
      expect(configurableRuleNames, containsAll(RuleRegistry.ruleNames));
      expect(configurableRuleNames, contains(Validator.skillFileInaccessible));
    });

    test('reflects changes to RuleRegistry.allChecks', () {
      const check = CheckType(
        name: 'temporary-test-rule',
        defaultSeverity: AnalysisSeverity.disabled,
        help: 'Temporary rule for testing.',
      );
      RuleRegistry.allChecks.add(check);
      addTearDown(() => RuleRegistry.allChecks.remove(check));

      expect(configurableRuleNames, contains('temporary-test-rule'));
    });
  });

  group('unknownRuleNameMessage', () {
    test('lists every equally close name', () {
      // Equally far from "check-absolute-paths" and "check-relative-paths".
      expect(
        unknownRuleNameMessage('check-reloluxe-paths', context: 'Global rules'),
        reportsUnknownRule(
          'check-reloluxe-paths',
          section: 'Global rules',
          suggestions: ['check-absolute-paths', 'check-relative-paths'],
        ),
      );
    });

    test('notes a newer skills_lint when no configurable name is close', () {
      expect(
        unknownRuleNameMessage('zzz', context: 'Global rules'),
        reportsUnknownRule('zzz', section: 'Global rules'),
      );
    });
  });

  group('mergeKeyMessage', () {
    test('explains that YAML merge keys are not supported', () {
      expect(
        mergeKeyMessage(context: 'Global rules'),
        allOf(contains('Global rules'), contains('YAML merge keys ("<<") are not supported')),
      );
    });
  });

  group('unknownRuleMessages', () {
    test('distinguishes custom rules, unknown rules, and configurable rules', () {
      final customRule = QuietRule();
      final List<String> messages = unknownRuleMessages(
        {
          customRule.name: const RuleConfigPatch(),
          'check-relative-path': const RuleConfigPatch(),
          'check-relative-paths': const RuleConfigPatch(),
        },
        context: 'resolvedRuleConfigs',
        customRules: [customRule],
      );

      expect(messages, [
        contains('"${customRule.name}" is a custom rule'),
        reportsUnknownRule(
          'check-relative-path',
          section: 'resolvedRuleConfigs',
          suggestions: ['check-relative-paths'],
        ),
      ]);
    });

    test('reports a custom rule named like a built-in rule as custom', () {
      final customRule = QuietRule(name: 'check-relative-pathz');
      final List<String> messages = unknownRuleMessages(
        {customRule.name: const RuleConfigPatch()},
        context: 'resolvedRuleConfigs',
        customRules: [customRule],
      );

      expect(messages, [contains('"${customRule.name}" is a custom rule')]);
      expect(messages.single, isNot(contains('check-relative-paths')));
    });
  });
}
