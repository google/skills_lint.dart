// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:skills_lint/skills_lint.dart';
import 'package:skills_lint/src/rules/absolute_paths_rule.dart';
import 'package:skills_lint/src/rules/path_does_not_exist_rule.dart';
import 'package:skills_lint/src/rules/prevent_skills_sh_publishing_rule.dart';
import 'package:skills_lint/src/rules/published_skill_name_rule.dart';
import 'package:skills_lint/src/rules/relative_paths_rule.dart';
import 'package:skills_lint/src/rules/trailing_whitespace_rule.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  group('Configuration YAML Round-trip Serialization', () {
    test('round-trips empty configuration', () {
      const config = Configuration();
      final String yamlString = config.toYamlString();

      expect(yamlString, contains('skills_lint:'));
      final Configuration parsed = ConfigParser.parse(yamlString);

      expect(parsed.toYamlString(), equals(config.toYamlString()));
    });

    test('round-trips global rules with scalar severities', () {
      const config = Configuration(
        ruleConfigs: {
          RelativePathsRule.ruleName: RuleConfigPatch(severity: AnalysisSeverity.error),
          AbsolutePathsRule.ruleName: RuleConfigPatch(severity: AnalysisSeverity.warning),
          TrailingWhitespaceRule.ruleName: RuleConfigPatch(severity: AnalysisSeverity.disabled),
        },
      );

      final String yamlString = config.toYamlString();
      final Configuration parsed = ConfigParser.parse(yamlString);

      expect(
        parsed.ruleConfigs[AbsolutePathsRule.ruleName]?.severity,
        equals(AnalysisSeverity.warning),
      );
      expect(
        parsed.ruleConfigs[TrailingWhitespaceRule.ruleName]?.severity,
        equals(AnalysisSeverity.disabled),
      );
      expect(parsed.toYamlString(), equals(config.toYamlString()));
    });

    test('round-trips global rules with custom parameters', () {
      final config = Configuration(
        ruleConfigs: {
          PathDoesNotExistRule.ruleName: RuleConfigPatch(
            severity: AnalysisSeverity.error,
            parameters: CustomRuleParameters(const {'exclude': '.*-workspace'}),
          ),
          PublishedSkillNameRule.ruleName: RuleConfigPatch(
            parameters: CustomRuleParameters(const {'package_name': 'my_package'}),
          ),
        },
      );

      final String yamlString = config.toYamlString();
      final Configuration parsed = ConfigParser.parse(yamlString);

      expect(parsed.toYamlString(), equals(config.toYamlString()));
    });

    test('round-trips directory target configurations', () {
      final config = Configuration(
        directoryConfigs: [
          const LintTargetConfig(
            path: 'skills',
            ruleConfigs: {
              TrailingWhitespaceRule.ruleName: RuleConfigPatch(severity: AnalysisSeverity.error),
              PublishedSkillNameRule.ruleName: RuleConfigPatch(severity: AnalysisSeverity.warning),
            },
            ignoreFile: 'skills/.skillsignore',
          ),
          LintTargetConfig(
            path: '../../.agents/skills',
            ruleConfigs: {
              PathDoesNotExistRule.ruleName: RuleConfigPatch(
                severity: AnalysisSeverity.error,
                parameters: CustomRuleParameters(const {'exclude': '.*-workspace'}),
              ),
            },
          ),
        ],
      );

      final String yamlString = config.toYamlString();
      final Configuration parsed = ConfigParser.parse(yamlString);

      final LintTargetConfig dir1 = parsed.directoryConfigs[0];
      expect(
        dir1.ruleConfigs[TrailingWhitespaceRule.ruleName]?.severity,
        equals(AnalysisSeverity.error),
      );

      final LintTargetConfig dir2 = parsed.directoryConfigs[1];
      expect(
        dir2.ruleConfigs[PathDoesNotExistRule.ruleName]?.parameters?['exclude'],
        equals('.*-workspace'),
      );
      expect(parsed.toYamlString(), equals(config.toYamlString()));
    });

    test('round-trips individual skill target configurations', () {
      const config = Configuration(
        individualSkillConfigs: [
          LintTargetConfig(
            path: '.agents/skills/add-dart-lint-validation-rule',
            ruleConfigs: {
              PreventSkillsShPublishingRule.ruleName: RuleConfigPatch(
                severity: AnalysisSeverity.error,
              ),
            },
            ignoreFile: 'custom_ignore.json',
          ),
          LintTargetConfig(
            path: '~/my-custom-skill',
            ruleConfigs: {
              RelativePathsRule.ruleName: RuleConfigPatch(severity: AnalysisSeverity.disabled),
            },
          ),
        ],
      );

      final String yamlString = config.toYamlString();
      final Configuration parsed = ConfigParser.parse(yamlString);

      final LintTargetConfig skill1 = parsed.individualSkillConfigs[0];
      expect(
        skill1.ruleConfigs[PreventSkillsShPublishingRule.ruleName]?.severity,
        equals(AnalysisSeverity.error),
      );

      final LintTargetConfig skill2 = parsed.individualSkillConfigs[1];
      expect(
        skill2.ruleConfigs[RelativePathsRule.ruleName]?.severity,
        equals(AnalysisSeverity.disabled),
      );
      expect(parsed.toYamlString(), equals(config.toYamlString()));
    });

    test('round-trips full composite configuration with all sections', () {
      final config = Configuration(
        ruleConfigs: const {
          RelativePathsRule.ruleName: RuleConfigPatch(severity: AnalysisSeverity.error),
          AbsolutePathsRule.ruleName: RuleConfigPatch(severity: AnalysisSeverity.error),
        },
        directoryConfigs: [
          LintTargetConfig(
            path: '../../.agents/skills',
            ruleConfigs: {
              TrailingWhitespaceRule.ruleName: const RuleConfigPatch(
                severity: AnalysisSeverity.error,
              ),
              PathDoesNotExistRule.ruleName: RuleConfigPatch(
                severity: AnalysisSeverity.error,
                parameters: CustomRuleParameters(const {'exclude': '.*-workspace'}),
              ),
            },
            ignoreFile: '../../.agents/skills/ignore.json',
          ),
          const LintTargetConfig(
            path: 'skills',
            ruleConfigs: {
              TrailingWhitespaceRule.ruleName: RuleConfigPatch(severity: AnalysisSeverity.error),
              PublishedSkillNameRule.ruleName: RuleConfigPatch(severity: AnalysisSeverity.error),
            },
          ),
        ],
        individualSkillConfigs: const [
          LintTargetConfig(
            path: '../../.agents/skills/add-dart-lint-validation-rule',
            ruleConfigs: {
              PreventSkillsShPublishingRule.ruleName: RuleConfigPatch(
                severity: AnalysisSeverity.error,
              ),
            },
          ),
        ],
      );

      final String yamlString = config.toYamlString();
      final Configuration parsed = ConfigParser.parse(yamlString);

      expect(parsed.toYamlString(), equals(config.toYamlString()));
    });
  });

  group('Model toYaml / toYamlString Methods', () {
    test('Configuration methods produce valid maps and strings', () {
      const config = Configuration(
        ruleConfigs: {
          RelativePathsRule.ruleName: RuleConfigPatch(severity: AnalysisSeverity.error),
        },
        directoryConfigs: [
          LintTargetConfig(
            path: 'skills',
            ruleConfigs: {
              TrailingWhitespaceRule.ruleName: RuleConfigPatch(severity: AnalysisSeverity.warning),
            },
          ),
        ],
      );

      final Map<String, Object?> yamlMap = config.toYaml();
      expect(yamlMap.containsKey('skills_lint'), isTrue);

      final String yamlStr = config.toYamlString();
      expect(yamlStr, contains('skills_lint:'));
      expect(yamlStr, contains('check-relative-paths: error'));
      expect(yamlStr, contains('path: skills'));
    });

    test('LintTargetConfig methods serialize correctly', () {
      const target = LintTargetConfig(
        path: 'skills/my_skill',
        ruleConfigs: {
          PublishedSkillNameRule.ruleName: RuleConfigPatch(severity: AnalysisSeverity.error),
        },
        ignoreFile: 'ignore.json',
      );

      final Map<String, Object?> map = target.toYaml();
      expect(map['path'], equals('skills/my_skill'));
      expect(map['ignore_file'], equals('ignore.json'));
      expect(map['rules'], equals({PublishedSkillNameRule.ruleName: 'error'}));

      final String yamlStr = target.toYamlString();
      expect(yamlStr, contains('path: skills/my_skill'));
      expect(yamlStr, contains('ignore_file: ignore.json'));
      expect(yamlStr, contains('published-skill-name: error'));
    });

    test('RuleConfig methods serialize correctly', () {
      const simpleConfig = RuleConfig(severity: AnalysisSeverity.error);
      expect(simpleConfig.toYaml(), equals('error'));
      expect(simpleConfig.toYamlString(), contains('error'));

      final complexConfig = RuleConfig(
        severity: AnalysisSeverity.warning,
        parameters: CustomRuleParameters(const {'chars': 500, 'strict': true}),
      );
      final Map<String, Object?> expectedMap = {
        'chars': 500,
        'strict': true,
        'severity': 'warning',
      };
      expect(complexConfig.toYaml(), equals(expectedMap));
      expect(complexConfig.toYamlString(), contains('severity: warning'));
      expect(complexConfig.toYamlString(), contains('chars: 500'));
    });

    test('RuleConfigPatch methods serialize correctly', () {
      const severityOnly = RuleConfigPatch(severity: AnalysisSeverity.disabled);
      expect(severityOnly.toYaml(), equals('disabled'));
      expect(severityOnly.toYamlString(), contains('disabled'));

      final paramsOnly = RuleConfigPatch(
        parameters: CustomRuleParameters(const {'exclude': '.*-test'}),
      );
      expect(paramsOnly.toYaml(), equals({'exclude': '.*-test'}));

      const emptyPatch = RuleConfigPatch();
      expect(emptyPatch.toYaml(), equals(<String, Object?>{}));
    });

    test('CustomRuleParameters methods serialize correctly', () {
      final params = CustomRuleParameters(const {
        'name': 'test',
        'count': 42,
        'enabled': false,
        'items': ['a', 'b'],
      });

      final Map<String, Object?> map = params.toYaml();
      expect(map['name'], equals('test'));
      expect(map['count'], equals(42));
      expect(map['enabled'], equals(false));
      expect(map['items'], equals(['a', 'b']));

      final String yamlStr = params.toYamlString();
      expect(yamlStr, contains('name: test'));
      expect(yamlStr, contains('count: 42'));
      expect(yamlStr, contains('enabled: false'));
    });
  });

  group('ConfigSerializer Standalone Helper', () {
    test('ConfigSerializer.toYamlString formats primitives and collections', () {
      expect(ConfigSerializer.toYamlString(null).trim(), equals('null'));
      expect(ConfigSerializer.toYamlString(true).trim(), equals('true'));
      expect(ConfigSerializer.toYamlString(false).trim(), equals('false'));
      expect(ConfigSerializer.toYamlString(123).trim(), equals('123'));
      expect(ConfigSerializer.toYamlString(3.14).trim(), equals('3.14'));
      expect(ConfigSerializer.toYamlString('hello').trim(), equals('hello'));

      // Reserved keywords or number-like strings are quoted
      expect(ConfigSerializer.toYamlString('true').trim(), equals('"true"'));
      expect(ConfigSerializer.toYamlString('123').trim(), equals('"123"'));
      expect(ConfigSerializer.toYamlString('null').trim(), equals('"null"'));
      expect(ConfigSerializer.toYamlString('').trim(), equals('""'));

      // Escaping special characters
      final String escaped = ConfigSerializer.toYamlString('line 1\nline 2');
      expect(escaped, contains(r'\n'));
    });
  });

  group('ConfigParser.parse Error Handling', () {
    test('records parsing errors on malformed YAML syntax', () {
      final Configuration config = ConfigParser.parse(': invalid: [');
      expect(config.parsingErrors, isNotEmpty);
      expect(config.parsingErrors.first, contains('Failed to parse content'));
    });

    test('records error on unrecognized top-level key', () {
      final Configuration config = ConfigParser.parse('''
skills_lint:
  unknown_key: value
''');
      expect(config.parsingErrors, isNotEmpty);
      expect(config.parsingErrors.first, contains('Unrecognized top-level key "unknown_key"'));
    });

    test('records parsing error on unknown rule severity', () {
      final Configuration config = ConfigParser.parse('''
skills_lint:
  rules:
    check-relative-paths: eror
''');
      expect(config.parsingErrors, isNotEmpty);
      expect(
        config.parsingErrors.first,
        contains('Invalid severity "eror" for rule "check-relative-paths"'),
      );
    });

    test('records parsing error on non-map top-level YAML', () {
      final Configuration config = ConfigParser.parse('"scalar string"');
      expect(config.parsingErrors, isNotEmpty);
      expect(config.parsingErrors.first, contains('Top-level configuration must be a YAML map'));
    });

    test('records parsing error on non-map skills_lint block', () {
      final Configuration config = ConfigParser.parse('''
skills_lint: "not a map"
''');
      expect(config.parsingErrors, isNotEmpty);
      expect(config.parsingErrors.first, contains('Expected "skills_lint" to be a YAML map'));
    });

    test('returns empty configuration on content without skills_lint map', () {
      final Configuration config = ConfigParser.parse('other_tool: 123');
      expect(config.directoryConfigs, isEmpty);
      expect(config.individualSkillConfigs, isEmpty);
      expect(config.ruleConfigs, isEmpty);
      expect(config.parsingErrors, isEmpty);
    });
  });

  group('Comprehensive Property & Golden Tests', () {
    test('golden test: exact emitted YAML matches expected string', () {
      final config = Configuration(
        ruleConfigs: {
          RelativePathsRule.ruleName: const RuleConfigPatch(severity: AnalysisSeverity.error),
          PathDoesNotExistRule.ruleName: RuleConfigPatch(
            severity: AnalysisSeverity.warning,
            parameters: CustomRuleParameters(const {'exclude': '.*-workspace', 'limit': 100}),
          ),
        },
        directoryConfigs: const [
          LintTargetConfig(
            path: 'skills',
            ignoreFile: 'custom_ignore.json',
            ruleConfigs: {
              TrailingWhitespaceRule.ruleName: RuleConfigPatch(severity: AnalysisSeverity.error),
            },
          ),
        ],
      );

      final String yamlString = config.toYamlString();
      const expected = '''
skills_lint:
  rules:
    check-relative-paths: error
    path-does-not-exist:
      exclude: ".*-workspace"
      limit: 100
      severity: warning
  directories:
    - path: skills
      rules:
        check-trailing-whitespace: error
      ignore_file: custom_ignore.json
''';
      expect(yamlString, equals(expected));
    });

    test('round-trips rule configurations with rich parameter types', () {
      final config = Configuration(
        ruleConfigs: {
          'custom-rule': RuleConfigPatch(
            severity: AnalysisSeverity.error,
            parameters: CustomRuleParameters(const {
              'count': 42,
              'enabled': true,
              'tags': ['a', 'b', 'c'],
              'numbers': [1, 2, 3],
              'nested': {'k1': 'v1', 'k2': 10},
            }),
          ),
        },
      );

      final String yamlString = config.toYamlString();
      final Configuration parsed = ConfigParser.parse(yamlString);

      expect(parsed.toYamlString(), equals(config.toYamlString()));
    });

    test('scalar quoting and escaping round-trips all tricky tokens cleanly', () {
      final testCases = <String>[
        '007',
        '0x1F',
        '0o17',
        '-',
        '-1',
        '+1',
        '.5',
        '1.2.3',
        '1e5',
        'true',
        'false',
        'True',
        'False',
        'TRUE',
        'FALSE',
        'null',
        'Null',
        'NULL',
        '~',
        'yes',
        'no',
        'on',
        'off',
        'nan',
        'inf',
        '+inf',
        '-inf',
        'infinity',
        'check-relative-paths',
        'skills/nested',
        '../../.agents/skills',
        '~/my-skill',
        'foo: bar',
        '#comment',
        'hello\nworld',
        'line1\r\nline2',
        'tab\tseparated',
        'quoted "double" and \'single\'',
        'special chars: @ ` | > % & * ! ? [ ] { } ,',
        'null byte: \x00',
        'control char: \x1f',
        'del char: \x7f',
        'unicode: 🚀 🎯 — «»',
      ];

      for (final s in testCases) {
        final String yaml = ConfigSerializer.toYamlString(s);
        final Object? loaded = loadYaml(yaml);
        expect(
          loaded,
          equals(s),
          reason: 'Failed to round-trip scalar: "$s" (emitted YAML: $yaml)',
        );
      }
    });

    test('CustomRuleParameters ensures deep immutability for nested collections', () {
      final list = ['a', 'b'];
      final nestedMap = {'k': 'v'};
      final params = CustomRuleParameters({'items': list, 'nested': nestedMap});

      expect(() => (params['items']! as List<Object?>).add('c'), throwsUnsupportedError);
      expect(
        () => (params['nested']! as Map<String, Object?>)['new'] = 'val',
        throwsUnsupportedError,
      );
    });

    test('CustomRuleParameters key named severity does not overwrite rule severity', () {
      final patch = RuleConfigPatch(
        severity: AnalysisSeverity.error,
        parameters: CustomRuleParameters(const {'severity': 'ignored_param'}),
      );
      final Object? yamlObj = patch.toYaml();
      expect(yamlObj, isA<Map<String, Object?>>());
      final Map<String, Object?> map = (yamlObj as Map<String, Object?>?)!;
      expect(map[ConfigParser.severityKey], equals('error'));
    });
  });
}
