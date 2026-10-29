// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_lint/skills_lint.dart';
import 'package:skills_lint/src/path_utils.dart';
import 'package:skills_lint/src/unknown_rule_names.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// Matches a message that reports [name] as unknown, in the section labeled
/// [section], suggesting each of [suggestions] and showing [location].
///
/// It checks the parts that matter rather than the exact wording, so a
/// change in punctuation does not break it.
Matcher _reportsUnknown(
  String name, {
  String? section,
  List<String> suggestions = const [],
  String? location,
}) => allOf([
  contains('Unknown rule "$name"'),
  if (section != null) contains(section),
  for (final suggestion in suggestions) contains('"$suggestion"'),
  if (suggestions.isEmpty) contains('newer skills_lint'),
  if (location != null) contains(location),
]);

void main() {
  group('unknownRuleNameMessage', () {
    test('lists every equally close name', () {
      // Equally far from "check-absolute-paths" and "check-relative-paths".
      expect(
        unknownRuleNameMessage('check-reloluxe-paths', context: 'Global rules'),
        _reportsUnknown(
          'check-reloluxe-paths',
          suggestions: ['check-absolute-paths', 'check-relative-paths'],
        ),
      );
    });

    test('treats skill-file-inaccessible as configurable', () {
      expect(configurableRuleNames, contains('skill-file-inaccessible'));
    });
  });

  group('ConfigParser', () {
    test('reports each kind of typo in the top-level rules and leaves it out', () {
      final Configuration config = ConfigParser.parse('''
skills_lint:
  rules:
    check-relative-path: error
    check_absolute_paths: error
    valid-ymal-metadata: error
    invalid-skil-name: error
    zzz: error
    description-too-long: warning
''');

      expect(config.parsingErrors, [
        // A dropped character.
        _reportsUnknown('check-relative-path', suggestions: ['check-relative-paths']),
        // Underscores instead of hyphens.
        _reportsUnknown('check_absolute_paths', suggestions: ['check-absolute-paths']),
        // Two letters swapped.
        _reportsUnknown('valid-ymal-metadata', suggestions: ['valid-yaml-metadata']),
        // A dropped letter in the middle.
        _reportsUnknown('invalid-skil-name', suggestions: ['invalid-skill-name']),
        // Nothing close: may be a rule from a newer skills_lint.
        _reportsUnknown('zzz'),
      ]);
      expect(config.ruleConfigs.keys, ['description-too-long']);
    });

    test('reports typos in target entries', () {
      final Configuration config = ConfigParser.parse('''
skills_lint:
  directories:
    - path: .agents/skills
      rules:
        valid-yaml-metadat: error
  individual_skills:
    - path: one/skill
      rules:
        check-trailing-whitespace-: error
''');

      expect(config.parsingErrors, [
        _reportsUnknown(
          'valid-yaml-metadat',
          section: '".agents/skills"',
          suggestions: ['valid-yaml-metadata'],
        ),
        _reportsUnknown(
          'check-trailing-whitespace-',
          section: '"one/skill"',
          suggestions: ['check-trailing-whitespace'],
        ),
      ]);
    });

    test('accepts skill-file-inaccessible', () {
      final Configuration config = ConfigParser.parse('''
skills_lint:
  rules:
    skill-file-inaccessible: warning
''');

      expect(config.parsingErrors, isEmpty);
      expect(config.ruleConfigs.keys, ['skill-file-inaccessible']);
    });

    test('reports a custom rule name, because configuration does not affect custom rules', () {
      final Configuration config = ConfigParser.parse(
        Configuration(
          ruleConfigs: {_NoopRule().name: const RuleConfigPatch(severity: AnalysisSeverity.error)},
        ).toYamlString(),
      );

      expect(config.parsingErrors.single, contains('Unknown rule "${_NoopRule().name}"'));
    });

    test('explains a plain YAML merge key, and treats a quoted one as a name', () {
      final Configuration config = ConfigParser.parse('''
skills_lint:
  rules:
    base: &base
      severity: error
    <<: *base
  directories:
    - path: a
      rules:
        "<<": error
''');

      expect(config.parsingErrors, [
        _reportsUnknown('base'),
        allOf(
          contains('YAML merge keys ("<<") are not supported'),
          isNot(contains('Did you mean')),
        ),
        _reportsUnknown('<<', section: '"a"'),
      ]);
    });

    group('from a file', () {
      late Directory tempDir;

      setUp(() => tempDir = Directory.systemTemp.createTempSync('unknown_rule_names_test.'));
      tearDown(() => tempDir.deleteSync(recursive: true));

      /// Writes [yaml] to [name] in [tempDir] and returns the path the parser
      /// shows for it.
      String write(String name, String yaml) {
        final String path = p.join(tempDir.path, name);
        File(path).writeAsStringSync(yaml);
        return canonicalizePath(path, baseDirectory: Directory.current.path);
      }

      test('shows the line of each name, in block, multi-line and flow entries', () async {
        final String file = write('custom.yaml', '''
skills_lint:
  rules:
    check-relative-path: error
  directories:
    - path:
        skills
      rules:
        valid-yaml-metadat: error
    - {path: a, rules: {nope-rule: error}}
''');

        final Configuration config = await ConfigParser.loadConfig(path: file);

        expect(config.parsingErrors, [
          _reportsUnknown(
            'check-relative-path',
            suggestions: ['check-relative-paths'],
            location: '$file:3',
          ),
          _reportsUnknown(
            'valid-yaml-metadat',
            suggestions: ['valid-yaml-metadata'],
            location: '$file:8',
          ),
          _reportsUnknown('nope-rule', location: '$file:9'),
        ]);
      });

      test('shows the line of a merge key', () async {
        final String file = write('skills_lint.yaml', '''
skills_lint:
  rules:
    <<: {}
''');

        final Configuration config = await ConfigParser.loadConfig(path: file);

        expect(config.parsingErrors.single, contains('$file:3'));
      });
    });
  });

  test('the setup example harness pattern fails on a typo', () {
    final Configuration config = ConfigParser.parse('''
skills_lint:
  rules:
    check-relative-path: error
''');

    // Mirrors skills/skills-lint-setup/references/validate_skills_example.dart.
    expect(config.parsingErrors, isNot(isEmpty));
  });

  group('validateSkills', () {
    late Directory tempDir;
    late String skillPath;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('unknown_rule_names_api.');
      final Directory skill = await createDummySkill(
        tempDir,
        name: 'my-skill',
        skillContent: '${buildFrontmatter(name: 'my-skill')}Body.\n',
      );
      skillPath = skill.path;
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    Future<(bool, String)> run({
      Configuration? config,
      Map<String, RuleConfigPatch> resolvedRuleConfigs = const {},
      List<SkillRule> customRules = const [],
    }) async {
      final err = CapturedOutput();
      final bool passed = await IOOverrides.runZoned(
        () => validateSkills(
          individualSkillPaths: [skillPath],
          config: config,
          resolvedRuleConfigs: resolvedRuleConfigs,
          customRules: customRules,
          quiet: true,
        ),
        stderr: () => err,
      );
      return (passed, err.buffer.toString());
    }

    test('warns about a typo in a parsed configuration, once, and passes', () async {
      final (bool passed, String err) = await run(
        config: ConfigParser.parse('''
skills_lint:
  rules:
    check-relative-path: error
'''),
      );

      expect(err, contains('Configuration warning:'));
      expect(err, _reportsUnknown('check-relative-path', suggestions: ['check-relative-paths']));
      expect('Unknown rule'.allMatches(err), hasLength(1));
      expect(passed, isTrue);
    });

    test('warns about typos in a configuration built in code', () async {
      final (_, String err) = await run(
        config: const Configuration(
          ruleConfigs: {'check-absolute-path': RuleConfigPatch(severity: AnalysisSeverity.error)},
          individualSkillConfigs: [
            LintTargetConfig(
              path: 'my-skill',
              ruleConfigs: {'valid_yaml_metadata': RuleConfigPatch()},
            ),
          ],
        ),
      );

      expect(err, _reportsUnknown('check-absolute-path', suggestions: ['check-absolute-paths']));
      expect(
        err,
        _reportsUnknown(
          'valid_yaml_metadata',
          section: '"my-skill"',
          suggestions: ['valid-yaml-metadata'],
        ),
      );
    });

    test('warns about a typo in resolvedRuleConfigs', () async {
      final (_, String err) = await run(
        resolvedRuleConfigs: {'pub-archive-include-skill': const RuleConfigPatch()},
      );

      expect(
        err,
        _reportsUnknown(
          'pub-archive-include-skill',
          section: 'resolvedRuleConfigs',
          suggestions: ['pub-archive-includes-skill'],
        ),
      );
    });

    test('explains that configuration cannot set a custom rule', () async {
      final rule = _NoopRule();

      final (_, String err) = await run(
        resolvedRuleConfigs: {rule.name: const RuleConfigPatch()},
        customRules: [rule],
      );

      expect(err, contains('"${rule.name}" is a custom rule'));
      expect(err, isNot(contains('Unknown rule')));
    });

    test('accepts built-in names', () async {
      final (_, String err) = await run(
        resolvedRuleConfigs: {'valid-yaml-metadata': const RuleConfigPatch()},
      );

      expect(err, isNot(contains('Configuration warning')));
    });
  });
}

/// A custom rule that finds nothing, for checking how its name is handled.
class _NoopRule extends SkillRule {
  @override
  String get name => 'my-custom-rule';

  @override
  AnalysisSeverity get severity => AnalysisSeverity.disabled;

  @override
  Future<List<ValidationError>> validate(SkillContext context) async => const [];
}
