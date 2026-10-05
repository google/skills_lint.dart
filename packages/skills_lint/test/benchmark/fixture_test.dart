// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_lint/src/rule_registry.dart';
import 'package:test/test.dart';
import 'package:test_process/test_process.dart';

import '../../benchmark/src/fixture.dart';
import '../../benchmark/src/suite.dart';
import '../test_utils.dart';

final Set<String> _registeredRules = {for (final check in RuleRegistry.allChecks) check.name};

void main() {
  final List<SampleSkill> samples = readSampleSkills();
  final SampleSkill small = samples.firstWhere((t) => t.name == 'format-dart-code');

  test('has one violation for each registered rule, and plants every one', () {
    expect(violations.keys.toSet(), _registeredRules);
    expect({for (final rules in plantedViolations) ...rules}, _registeredRules);
    expect(plantedViolations.where((rules) => rules.length > 1), isNotEmpty);
  });

  test('reads the sample skills', () {
    expect(
      [for (final t in samples) t.name],
      ['format-dart-code', 'release-dart-package', 'triage-github-issues'],
    );
    for (final t in samples) {
      expect(t.firstReference, startsWith('references/'), reason: t.name);
    }
  });

  test('reads a sample skill checked out with CRLF line endings', () {
    final Directory dir = Directory.systemTemp.createTempSync('fixture_test.');
    addTearDown(() => dir.deleteSync(recursive: true));
    File(p.join(dir.path, 'SKILL.md')).writeAsStringSync(
      '---\r\nname: crlf\r\ndescription: Uses CRLF.\r\nmetadata:\r\n  internal: true\r\n---\r\n\r\n# Body\r\n',
    );
    File(p.join(dir.path, 'references', 'a.md'))
      ..createSync(recursive: true)
      ..writeAsStringSync('A\r\n');

    final sample = SampleSkill.read(dir);

    expect(sample.name, 'crlf');
    expect(sample.body, '# Body\n');
    expect(sample.files, {'references/a.md': 'A\n'});
  });

  group('fixtureSkill', () {
    test('gives the first skill the first planted violations', () {
      final FixtureSkill skill = fixtureSkill(0, samples);

      expect(skill.name, '${skill.directoryName}-renamed');
      expect(skill.bodySuffix, endsWith(' \n'));
    });

    test('leaves skills between planted ones valid', () {
      final FixtureSkill skill = fixtureSkill(1, samples);

      expect(skill.name, skill.directoryName);
      expect(skill.internal, isTrue);
      expect(skill.fields, skill.sample.fields);
      expect(skill.bodySuffix, isEmpty);
    });
  });

  group('renderSkillMd', () {
    test('writes the frontmatter and then the sample skill body', () {
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
      expect(rendered, contains('- [Link](references/style-notess.md)\n'));
      expect(rendered, contains('- [Link](${p.join(dir, 'references', 'style-notes.md')})\n'));
    });
  });

  cliTests();
}

/// The tests that run the CLI, which `compiled_test/` also runs against the
/// compiled binary.
void cliTests() {
  final List<SampleSkill> samples = readSampleSkills();

  test('every registered rule reports at least once on the fixture', () async {
    final Directory tempDir = Directory.systemTemp.createTempSync('fixture_test.');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    writeFixture(tempDir.path, invalidEvery * plantedViolations.length, samples: samples);

    final TestProcess process = await startCli([
      '--format',
      'json',
    ], workingDirectory: tempDir.path);
    final String stdout = await process.stdoutStream().join('\n');
    await process.shouldExit(expectedExitCode);

    final List<Map<String, Object?>> results = (jsonDecode(stdout) as List)
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
    expect(
      errors.where((skillErrors) => skillErrors.isNotEmpty),
      hasLength(plantedViolations.length),
      reason: 'Only the skills with planted violations report, so the sample skills are valid.',
    );
  });
}
