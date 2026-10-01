// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_lint/src/rule_registry.dart';
import 'package:test/test.dart';

import '../../benchmark/src/fixture.dart';
import '../../benchmark/src/suite.dart';

final Set<String> _registeredRules = {for (final check in RuleRegistry.allChecks) check.name};

void main() {
  final List<SkillTemplate> templates = readTemplates();
  final SkillTemplate small = templates.firstWhere((t) => t.name == 'small');

  test('has one violation for each registered rule, and plants every one', () {
    expect(violations.keys.toSet(), _registeredRules);
    expect({for (final rules in plantedViolations) ...rules}, _registeredRules);
    expect(plantedViolations.where((rules) => rules.length > 1), isNotEmpty);
  });

  test('reads the small, medium and large templates', () {
    expect([for (final t in templates) t.name], ['large', 'medium', 'small']);
    for (final t in templates) {
      expect(t.firstReference, startsWith('references/'), reason: t.name);
    }
  });

  group('fixtureSkill', () {
    test('gives the first skill the first planted violations', () {
      final FixtureSkill skill = fixtureSkill(0, templates);

      expect(skill.name, '${skill.directoryName}-renamed');
      expect(skill.bodySuffix, endsWith(' \n'));
    });

    test('leaves skills between planted ones valid', () {
      final FixtureSkill skill = fixtureSkill(1, templates);

      expect(skill.name, skill.directoryName);
      expect(skill.internal, isTrue);
      expect(skill.fields, isEmpty);
      expect(skill.bodySuffix, isEmpty);
    });
  });

  group('renderSkillMd', () {
    test('writes the frontmatter and then the template body', () {
      final skill = FixtureSkill(small, 'skill-0001');

      expect(
        renderSkillMd(skill, '/root/skill-0001'),
        '---\n'
        'name: skill-0001\n'
        'description: ${skill.description}\n'
        'metadata:\n'
        '  internal: true\n'
        '---\n'
        '\n'
        '${small.body}',
      );
    });

    test('writes the edits of a violation', () {
      final skill = FixtureSkill(small, 'skill-0001');
      violations['disallowed-field']!(skill);
      violations['check-relative-paths']!(skill);
      violations['check-absolute-paths']!(skill);
      final String dir = p.join(p.separator, 'root', 'skill-0001');

      final String rendered = renderSkillMd(skill, dir);

      expect(rendered, contains('owner: benchmarks\n'));
      expect(rendered, contains('- [Link](references/guides.md)\n'));
      expect(rendered, contains('- [Link](${p.join(dir, 'references', 'guide.md')})\n'));
    });
  });

  test('every registered rule reports at least once on the fixture', () async {
    final Directory tempDir = Directory.systemTemp.createTempSync('fixture_test.');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    writeFixture(tempDir.path, invalidEvery * plantedViolations.length, templates: templates);

    final ProcessResult result = await Process.run(Platform.resolvedExecutable, [
      p.absolute('bin', 'skills_lint.dart'),
      '--format',
      'json',
    ], workingDirectory: tempDir.path);

    expect(result.exitCode, expectedExitCode, reason: result.stderr as String);
    final List<Map<String, Object?>> results = (jsonDecode(result.stdout as String) as List)
        .cast<Map<String, Object?>>();
    final List<List<Map<String, Object?>>> errors = [
      for (final skill in results)
        (skill['validationErrors']! as List).cast<Map<String, Object?>>(),
    ];
    expect({
      for (final skillErrors in errors)
        for (final error in skillErrors) error['ruleId']! as String,
    }, _registeredRules);
    expect(errors.where((skillErrors) => skillErrors.length > 1), isNotEmpty);
  });
}
