// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:skills_lint/skills_lint.dart';
import 'package:test/test.dart';

void main() {
  group('Configuration YAML Round-trip Serialization', () {
    test('round-trips empty configuration', () {
      const config = Configuration();
      final String yamlString = config.toYamlString();

      expect(yamlString, contains('skills_lint:'));
      final Configuration parsed = ConfigParser.parse(yamlString);

      expect(parsed.directoryConfigs, isEmpty);
      expect(parsed.individualSkillConfigs, isEmpty);
      expect(parsed.ruleConfigs, isEmpty);
      expect(parsed.parsingErrors, isEmpty);
      expect(parsed, equals(config));
    });

    test('round-trips global rules with scalar severities', () {
      const config = Configuration(
        ruleConfigs: {
          'check-relative-paths': RuleConfigPatch(severity: AnalysisSeverity.error),
          'check-absolute-paths': RuleConfigPatch(severity: AnalysisSeverity.warning),
          'trailing-whitespace': RuleConfigPatch(severity: AnalysisSeverity.disabled),
        },
      );

      final String yamlString = config.toYamlString();
      final Configuration parsed = ConfigParser.parse(yamlString);

      expect(parsed.parsingErrors, isEmpty);
      expect(parsed.ruleConfigs.length, equals(3));
      expect(parsed.ruleConfigs['check-relative-paths']?.severity, equals(AnalysisSeverity.error));
      expect(
        parsed.ruleConfigs['check-absolute-paths']?.severity,
        equals(AnalysisSeverity.warning),
      );
      expect(
        parsed.ruleConfigs['trailing-whitespace']?.severity,
        equals(AnalysisSeverity.disabled),
      );
      expect(parsed, equals(config));
    });

    test('round-trips global rules with custom parameters', () {
      final config = Configuration(
        ruleConfigs: {
          'path-does-not-exist': RuleConfigPatch(
            severity: AnalysisSeverity.error,
            parameters: CustomRuleParameters(const {'exclude': '.*-workspace'}),
          ),
          'description-length': RuleConfigPatch(
            parameters: CustomRuleParameters(const {'chars': 500}),
          ),
        },
      );

      final String yamlString = config.toYamlString();
      final Configuration parsed = ConfigParser.parse(yamlString);

      expect(parsed.parsingErrors, isEmpty);
      expect(parsed.ruleConfigs.length, equals(2));

      final RuleConfigPatch? pathRule = parsed.ruleConfigs['path-does-not-exist'];
      expect(pathRule?.severity, equals(AnalysisSeverity.error));
      expect(pathRule?.parameters?['exclude'], equals('.*-workspace'));

      final RuleConfigPatch? descRule = parsed.ruleConfigs['description-length'];
      expect(descRule?.severity, isNull);
      expect(descRule?.parameters?['chars'], equals(500));
      expect(parsed, equals(config));
    });

    test('round-trips directory target configurations', () {
      final config = Configuration(
        directoryConfigs: [
          const LintTargetConfig(
            path: 'skills',
            ruleConfigs: {
              'check-trailing-whitespace': RuleConfigPatch(severity: AnalysisSeverity.error),
              'published-skill-name': RuleConfigPatch(severity: AnalysisSeverity.warning),
            },
            ignoreFile: 'skills/.skillsignore',
          ),
          LintTargetConfig(
            path: '../../.agents/skills',
            ruleConfigs: {
              'path-does-not-exist': RuleConfigPatch(
                severity: AnalysisSeverity.error,
                parameters: CustomRuleParameters(const {'exclude': '.*-workspace'}),
              ),
            },
          ),
        ],
      );

      final String yamlString = config.toYamlString();
      final Configuration parsed = ConfigParser.parse(yamlString);

      expect(parsed.parsingErrors, isEmpty);
      expect(parsed.directoryConfigs.length, equals(2));

      final LintTargetConfig dir1 = parsed.directoryConfigs[0];
      expect(dir1.path, equals('skills'));
      expect(dir1.ignoreFile, equals('skills/.skillsignore'));
      expect(
        dir1.ruleConfigs['check-trailing-whitespace']?.severity,
        equals(AnalysisSeverity.error),
      );
      expect(dir1.ruleConfigs['published-skill-name']?.severity, equals(AnalysisSeverity.warning));

      final LintTargetConfig dir2 = parsed.directoryConfigs[1];
      expect(dir2.path, equals('../../.agents/skills'));
      expect(dir2.ignoreFile, isNull);
      expect(
        dir2.ruleConfigs['path-does-not-exist']?.parameters?['exclude'],
        equals('.*-workspace'),
      );
      expect(parsed, equals(config));
    });

    test('round-trips individual skill target configurations', () {
      const config = Configuration(
        individualSkillConfigs: [
          LintTargetConfig(
            path: '.agents/skills/add-dart-lint-validation-rule',
            ruleConfigs: {
              'prevent-skills-sh-publishing': RuleConfigPatch(severity: AnalysisSeverity.error),
            },
            ignoreFile: 'custom_ignore.json',
          ),
          LintTargetConfig(
            path: '~/my-custom-skill',
            ruleConfigs: {
              'check-relative-paths': RuleConfigPatch(severity: AnalysisSeverity.disabled),
            },
          ),
        ],
      );

      final String yamlString = config.toYamlString();
      final Configuration parsed = ConfigParser.parse(yamlString);

      expect(parsed.parsingErrors, isEmpty);
      expect(parsed.individualSkillConfigs.length, equals(2));

      final LintTargetConfig skill1 = parsed.individualSkillConfigs[0];
      expect(skill1.path, equals('.agents/skills/add-dart-lint-validation-rule'));
      expect(skill1.ignoreFile, equals('custom_ignore.json'));
      expect(
        skill1.ruleConfigs['prevent-skills-sh-publishing']?.severity,
        equals(AnalysisSeverity.error),
      );

      final LintTargetConfig skill2 = parsed.individualSkillConfigs[1];
      expect(skill2.path, equals('~/my-custom-skill'));
      expect(
        skill2.ruleConfigs['check-relative-paths']?.severity,
        equals(AnalysisSeverity.disabled),
      );
      expect(parsed, equals(config));
    });

    test('round-trips full composite configuration with all sections', () {
      final config = Configuration(
        ruleConfigs: const {
          'check-relative-paths': RuleConfigPatch(severity: AnalysisSeverity.error),
          'check-absolute-paths': RuleConfigPatch(severity: AnalysisSeverity.error),
        },
        directoryConfigs: [
          LintTargetConfig(
            path: '../../.agents/skills',
            ruleConfigs: {
              'check-trailing-whitespace': const RuleConfigPatch(severity: AnalysisSeverity.error),
              'path-does-not-exist': RuleConfigPatch(
                severity: AnalysisSeverity.error,
                parameters: CustomRuleParameters(const {'exclude': '.*-workspace'}),
              ),
            },
            ignoreFile: '../../.agents/skills/ignore.json',
          ),
          const LintTargetConfig(
            path: 'skills',
            ruleConfigs: {
              'check-trailing-whitespace': RuleConfigPatch(severity: AnalysisSeverity.error),
              'published-skill-name': RuleConfigPatch(severity: AnalysisSeverity.error),
            },
          ),
        ],
        individualSkillConfigs: const [
          LintTargetConfig(
            path: '../../.agents/skills/add-dart-lint-validation-rule',
            ruleConfigs: {
              'prevent-skills-sh-publishing': RuleConfigPatch(severity: AnalysisSeverity.error),
            },
          ),
        ],
      );

      final String yamlString = config.toYamlString();
      final Configuration parsed = ConfigParser.parse(yamlString);

      expect(parsed.parsingErrors, isEmpty);
      expect(parsed, equals(config));
    });
  });

  group('Model toYaml / toYamlMap / toYamlString Methods', () {
    test('Configuration methods produce valid maps and strings', () {
      const config = Configuration(
        ruleConfigs: {'check-relative-paths': RuleConfigPatch(severity: AnalysisSeverity.error)},
        directoryConfigs: [
          LintTargetConfig(
            path: 'skills',
            ruleConfigs: {
              'check-trailing-whitespace': RuleConfigPatch(severity: AnalysisSeverity.warning),
            },
          ),
        ],
      );

      final Map<String, Object?> yamlMap = config.toYamlMap();
      expect(yamlMap.containsKey('skills_lint'), isTrue);
      expect(config.toYaml(), equals(yamlMap));

      final String yamlStr = config.toYamlString();
      expect(yamlStr, contains('skills_lint:'));
      expect(yamlStr, contains('check-relative-paths: error'));
      expect(yamlStr, contains('path: skills'));
    });

    test('LintTargetConfig methods serialize correctly', () {
      const target = LintTargetConfig(
        path: 'skills/my_skill',
        ruleConfigs: {'published-skill-name': RuleConfigPatch(severity: AnalysisSeverity.error)},
        ignoreFile: 'ignore.json',
      );

      final Map<String, Object?> map = target.toYamlMap();
      expect(map['path'], equals('skills/my_skill'));
      expect(map['ignore_file'], equals('ignore.json'));
      expect(map['rules'], equals({'published-skill-name': 'error'}));
      expect(target.toYaml(), equals(map));

      final String yamlStr = target.toYamlString();
      expect(yamlStr, contains('path: "skills/my_skill"'));
      expect(yamlStr, contains('ignore_file: "ignore.json"'));
      expect(yamlStr, contains('published-skill-name: error'));
    });

    test('RuleConfig methods serialize correctly', () {
      const simpleConfig = RuleConfig(severity: AnalysisSeverity.error);
      expect(simpleConfig.toYaml(), equals('error'));
      expect(simpleConfig.toYamlMap(), equals({'severity': 'error'}));
      expect(simpleConfig.toYamlString(), contains('error'));

      final complexConfig = RuleConfig(
        severity: AnalysisSeverity.warning,
        parameters: CustomRuleParameters(const {'chars': 500, 'strict': true}),
      );
      final Map<String, Object?> expectedMap = {
        'severity': 'warning',
        'chars': 500,
        'strict': true,
      };
      expect(complexConfig.toYaml(), equals(expectedMap));
      expect(complexConfig.toYamlMap(), equals(expectedMap));
      expect(complexConfig.toYamlString(), contains('severity: warning'));
      expect(complexConfig.toYamlString(), contains('chars: 500'));
    });

    test('RuleConfigPatch methods serialize correctly', () {
      const severityOnly = RuleConfigPatch(severity: AnalysisSeverity.disabled);
      expect(severityOnly.toYaml(), equals('disabled'));
      expect(severityOnly.toYamlMap(), equals({'severity': 'disabled'}));
      expect(severityOnly.toYamlString(), contains('disabled'));

      final paramsOnly = RuleConfigPatch(
        parameters: CustomRuleParameters(const {'exclude': '.*-test'}),
      );
      expect(paramsOnly.toYaml(), equals({'exclude': '.*-test'}));
      expect(paramsOnly.toYamlMap(), equals({'exclude': '.*-test'}));

      const emptyPatch = RuleConfigPatch();
      expect(emptyPatch.toYaml(), equals(<String, Object?>{}));
      expect(emptyPatch.toYamlMap(), equals(<String, Object?>{}));
    });

    test('CustomRuleParameters methods serialize correctly', () {
      final params = CustomRuleParameters(const {
        'name': 'test',
        'count': 42,
        'enabled': false,
        'items': ['a', 'b'],
      });

      final Map<String, Object?> map = params.toYamlMap();
      expect(map['name'], equals('test'));
      expect(map['count'], equals(42));
      expect(map['enabled'], equals(false));
      expect(map['items'], equals(['a', 'b']));
      expect(params.toYaml(), equals(map));

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

    test('ConfigSerializer supports model instances directly in toYamlString', () {
      const config = Configuration(
        ruleConfigs: {'check-relative-paths': RuleConfigPatch(severity: AnalysisSeverity.error)},
      );
      expect(ConfigSerializer.toYamlString(config), contains('skills_lint:'));
    });
  });

  group('Model Value Equality and HashCode', () {
    test('CustomRuleParameters equality and hashCode', () {
      final p1 = CustomRuleParameters(const {'a': 1, 'b': 'x'});
      final p2 = CustomRuleParameters(const {'a': 1, 'b': 'x'});
      final p3 = CustomRuleParameters(const {'a': 1, 'b': 'y'});

      expect(p1, equals(p2));
      expect(p1.hashCode, equals(p2.hashCode));
      expect(p1, isNot(equals(p3)));
      expect(p1.toString(), contains('CustomRuleParameters'));
    });

    test('RuleConfig equality and hashCode', () {
      final r1 = RuleConfig(
        severity: AnalysisSeverity.error,
        parameters: CustomRuleParameters(const {'a': 1}),
      );
      final r2 = RuleConfig(
        severity: AnalysisSeverity.error,
        parameters: CustomRuleParameters(const {'a': 1}),
      );
      final r3 = RuleConfig(
        severity: AnalysisSeverity.warning,
        parameters: CustomRuleParameters(const {'a': 1}),
      );

      expect(r1, equals(r2));
      expect(r1.hashCode, equals(r2.hashCode));
      expect(r1, isNot(equals(r3)));
      expect(r1.toString(), contains('RuleConfig'));
    });

    test('RuleConfigPatch equality and hashCode', () {
      final p1 = RuleConfigPatch(
        severity: AnalysisSeverity.error,
        parameters: CustomRuleParameters(const {'a': 1}),
      );
      final p2 = RuleConfigPatch(
        severity: AnalysisSeverity.error,
        parameters: CustomRuleParameters(const {'a': 1}),
      );
      const p3 = RuleConfigPatch(severity: AnalysisSeverity.error);

      expect(p1, equals(p2));
      expect(p1.hashCode, equals(p2.hashCode));
      expect(p1, isNot(equals(p3)));
      expect(p1.toString(), contains('RuleConfigPatch'));
    });

    test('LintTargetConfig equality and hashCode', () {
      const t1 = LintTargetConfig(
        path: 'skills',
        ruleConfigs: {'check-relative-paths': RuleConfigPatch(severity: AnalysisSeverity.error)},
        ignoreFile: 'ignore.json',
      );
      const t2 = LintTargetConfig(
        path: 'skills',
        ruleConfigs: {'check-relative-paths': RuleConfigPatch(severity: AnalysisSeverity.error)},
        ignoreFile: 'ignore.json',
      );
      const t3 = LintTargetConfig(path: 'other');

      expect(t1, equals(t2));
      expect(t1.hashCode, equals(t2.hashCode));
      expect(t1, isNot(equals(t3)));
      expect(t1.toString(), contains('LintTargetConfig'));
    });

    test('Configuration equality and hashCode', () {
      const c1 = Configuration(
        directoryConfigs: [
          LintTargetConfig(
            path: 'skills',
            ruleConfigs: {
              'check-relative-paths': RuleConfigPatch(severity: AnalysisSeverity.error),
            },
          ),
        ],
        ruleConfigs: {'check-relative-paths': RuleConfigPatch(severity: AnalysisSeverity.error)},
      );
      const c2 = Configuration(
        directoryConfigs: [
          LintTargetConfig(
            path: 'skills',
            ruleConfigs: {
              'check-relative-paths': RuleConfigPatch(severity: AnalysisSeverity.error),
            },
          ),
        ],
        ruleConfigs: {'check-relative-paths': RuleConfigPatch(severity: AnalysisSeverity.error)},
      );
      const c3 = Configuration();

      expect(c1, equals(c2));
      expect(c1.hashCode, equals(c2.hashCode));
      expect(c1, isNot(equals(c3)));
      expect(c1.toString(), contains('Configuration'));
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

    test('returns empty configuration on content without skills_lint map', () {
      final Configuration config = ConfigParser.parse('other_tool: 123');
      expect(config.directoryConfigs, isEmpty);
      expect(config.individualSkillConfigs, isEmpty);
      expect(config.ruleConfigs, isEmpty);
      expect(config.parsingErrors, isEmpty);
    });
  });
}
