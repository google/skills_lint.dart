// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_lint/src/models/analysis_severity.dart';
import 'package:skills_lint/src/models/skill_context.dart';
import 'package:skills_lint/src/models/validation_error.dart';
import 'package:skills_lint/src/rule_registry.dart';
import 'package:skills_lint/src/rules/frontmatter_truncated_by_comment_rule.dart';
import 'package:test/test.dart';
import 'package:test_process/test_process.dart';
import 'package:yaml/yaml.dart';

import 'test_utils.dart';

final _rule = FrontmatterTruncatedByCommentRule(severity: AnalysisSeverity.error);

/// A `SKILL.md` whose frontmatter is `name: my-skill` followed by
/// [frontmatterLines], joined with [lineEnding].
String _skillMd(List<String> frontmatterLines, {String lineEnding = '\n'}) =>
    ['---', 'name: my-skill', ...frontmatterLines, '---', '', 'Body.', ''].join(lineEnding);

SkillContext _context(String rawContent) =>
    createTestSkillContext(directory: Directory('my-skill'), rawContent: rawContent);

Future<List<ValidationError>> _validate(String rawContent) => _rule.validate(_context(rawContent));

/// The frontmatter of [rawContent], parsed.
YamlMap _frontmatter(String rawContent) =>
    loadYaml(SkillContext.skillStartRegex.firstMatch(rawContent)!.group(1)!) as YamlMap;

/// Runs the fix on [rawContent], checks that the rule reports nothing on the
/// result, and returns the fixed content.
Future<String> _fixClean(String rawContent, {Set<String> ignoredSubjects = const {}}) async {
  final String fixed = await _rule.fix(_context(rawContent), ignoredSubjects: ignoredSubjects);
  expect(await _validate(fixed), isEmpty, reason: 'The fix left findings in:\n$fixed');
  return fixed;
}

void main() {
  group('FrontmatterTruncatedByCommentRule.validate', () {
    test('reports a description that a comment cuts short', () async {
      final List<ValidationError> errors = await _validate(
        _skillMd(['description: Use when asked "fix #123" or to triage bugs.']),
      );

      expect(errors, hasLength(1));
      final ValidationError error = errors.single;
      expect(error.ruleId, FrontmatterTruncatedByCommentRule.ruleName);
      expect(error.severity, AnalysisSeverity.error);
      expect(error.file, 'SKILL.md');
      expect(error.subject, 'description');
      expect(
        error.message,
        '"description" is cut short at "#": YAML reads "Use when asked "fix" and drops '
        '"#123" or to triage bugs.". Quote the value to keep the full text, or move the '
        'comment to its own line.',
      );
      expect(error.markdownMessage, contains('whitespace followed by `#`'));
      // The region covers the dropped text on line 3, from `#` to the end.
      expect(error.region?.toJson(), {
        'startLine': 3,
        'startColumn': 34,
        'endLine': 3,
        'endColumn': 58,
      });
    });

    test('reports a tab before the #', () async {
      final List<ValidationError> errors = await _validate(
        _skillMd(['description: Fix bugs\t#1 first']),
      );

      expect(errors.single.message, contains('YAML reads "Fix bugs" and drops "#1 first"'));
    });

    test('reports the last line of a multi-line value', () async {
      final List<ValidationError> errors = await _validate(
        _skillMd(['description: Fix bugs', '  from the tracker #123 first']),
      );

      expect(errors.single.message, contains('YAML reads "Fix bugs from the tracker"'));
      expect(errors.single.region?.startLine, 4);
    });

    test('reports values in other fields, nested maps and lists', () async {
      final List<ValidationError> errors = await _validate(
        _skillMd([
          'description: Fine.',
          'compatibility: Needs git #2',
          'metadata:',
          '  short-description: Run the #1 check',
          '  tags:',
          '    - triage #bugs',
        ]),
      );

      expect(errors.map((e) => e.subject), [
        'compatibility',
        'metadata.short-description',
        'metadata.tags',
      ]);
    });

    test('gives every item of a list the path of the list', () async {
      final List<ValidationError> errors = await _validate(
        _skillMd(['description: Fine.', 'tags:', '  - triage #bugs', '  - fix #1']),
      );

      expect(errors.map((e) => e.subject), ['tags', 'tags']);
    });

    test('keeps the message on one line when the value has a blank line', () async {
      final List<ValidationError> errors = await _validate(
        _skillMd(['description: Fix bugs', '', '  from #1 first']),
      );

      expect(errors.single.message, contains(r'YAML reads "Fix bugs\nfrom" and drops "#1 first"'));
    });

    test('reports CRLF line endings without the carriage return', () async {
      final List<ValidationError> errors = await _validate(
        _skillMd(['description: Fix #1 now', 'license: MIT'], lineEnding: '\r\n'),
      );

      expect(errors.single.message, contains('drops "#1 now".'));
    });

    test('reports values in a multi-line flow collection', () async {
      final List<ValidationError> errors = await _validate(
        _skillMd([
          'description: Fine.',
          'metadata: { short-description: Run #1',
          '  , tags: [triage #bugs',
          '  ] }',
        ]),
      );

      expect(errors.map((e) => e.subject), ['metadata.short-description', 'metadata.tags']);
    });

    final notReported = <String, List<String>>{
      'a single-quoted value': ["description: 'Fix #123 now'"],
      'a double-quoted value': ['description: "Fix #123 now"'],
      'a literal block value': ['description: |', '  Fix #123 now'],
      'a folded block value': ['description: >-', '  Fix #123 now'],
      'C#': ['description: Write C# code'],
      'owner/repo#1': ['description: See owner/repo#1 for details'],
      'a # without whitespace before it': ['description: x#y'],
      'an empty value with a comment': ['description: # to do', 'license: MIT'],
      'a comment on its own line': ['description: Fix bugs', '# A comment', 'license: MIT'],
      'an indented comment line after a value': ['description: Fix bugs', '  # A comment'],
      'trailing whitespace without #': ['description: Fix bugs  '],
      'a comment after a non-string value': [
        'description: Fine.',
        'metadata:',
        '  internal: true # x',
      ],
      'a comment after a key with a block value': ['description: Fine.', 'metadata: # x', '  a: b'],
      // Quoting from the tag would pull the comment line into the value.
      'a value after a tag and a comment line': [
        'description: Fine.',
        'metadata:',
        '  tagged: !!str',
        '    # note',
        '    Fix #1 now',
      ],
    };
    for (final MapEntry(key: name, value: lines) in notReported.entries) {
      test('does not report $name', () async {
        expect(await _validate(_skillMd(lines)), isEmpty);
      });
    }

    test('does not report name, because a valid name has no whitespace or #', () async {
      const content = '---\nname: my-skill # the directory name\ndescription: Fine.\n---\n';

      expect(await _validate(content), isEmpty);
    });

    test('reports a value that an alias repeats once', () async {
      final List<ValidationError> errors = await _validate(
        _skillMd(['description: &d Fix #1 now', 'compatibility: *d']),
      );

      expect(errors.map((e) => e.subject), ['description']);
    });

    test('reports nothing without frontmatter or parsed YAML', () async {
      expect(await _validate('No frontmatter.\n'), isEmpty);
      final context = SkillContext(
        directory: Directory('my-skill'),
        rawContent: _skillMd(['description: Fix #1 now']),
      );
      expect(await _rule.validate(context), isEmpty);
    });

    test('reports nothing, without throwing, when parsedYaml is not from rawContent', () async {
      final String other = _skillMd(['description: A much longer value that ends #here']);
      final context = SkillContext(
        directory: Directory('my-skill'),
        rawContent: _skillMd(['description: Short']),
        parsedYaml: _frontmatter(other),
      );

      expect(await _rule.validate(context), isEmpty);
    });

    // The validator reads files without the BOM; this guards a context whose
    // offsets are one off from its parsedYaml.
    test('reports nothing, without throwing, when rawContent has a leading BOM', () async {
      final content = '\uFEFF${_skillMd(['description: Fix #1 now'])}';
      final context = SkillContext(
        directory: Directory('my-skill'),
        rawContent: content,
        parsedYaml: _frontmatter(content.substring(1)),
      );

      expect(await _rule.validate(context), isEmpty);
    });

    test('is disabled by default and registered', () {
      expect(FrontmatterTruncatedByCommentRule.defaultSeverity, AnalysisSeverity.disabled);
      expect(FrontmatterTruncatedByCommentRule().severity, AnalysisSeverity.disabled);
      expect(RuleRegistry.ruleNames, contains(FrontmatterTruncatedByCommentRule.ruleName));
      expect(
        RuleRegistry.createRule(
          FrontmatterTruncatedByCommentRule.ruleName,
          AnalysisSeverity.warning,
        ),
        isA<FrontmatterTruncatedByCommentRule>().having(
          (r) => r.severity,
          'severity',
          AnalysisSeverity.warning,
        ),
      );
    });
  });

  group('FrontmatterTruncatedByCommentRule.fix keeps the full text', () {
    /// Fixes a skill whose frontmatter is [lines], and checks that YAML reads
    /// [field] of the result as [expected].
    Future<String> expectRoundTrip(
      List<String> lines, {
      required String field,
      required Object expected,
      String lineEnding = '\n',
    }) async {
      final String fixed = await _fixClean(_skillMd(lines, lineEnding: lineEnding));
      expect(_frontmatter(fixed)[field], expected);
      return fixed;
    }

    test('quotes a description in single quotes', () async {
      final String fixed = await expectRoundTrip(
        ['description: Use when asked "fix #123" or to triage bugs.'],
        field: 'description',
        expected: 'Use when asked "fix #123" or to triage bugs.',
      );

      expect(fixed, contains('''description: 'Use when asked "fix #123" or to triage bugs.'\n'''));
    });

    test('doubles single quotes and keeps backslashes and colons', () async {
      await expectRoundTrip(
        [r"description: Don't fix #12 in C:\temp: it's \n not a newline"],
        field: 'description',
        expected: r"Don't fix #12 in C:\temp: it's \n not a newline",
      );
    });

    test('keeps a tab before the #', () async {
      await expectRoundTrip(
        ['description: Fix bugs\t#1 first'],
        field: 'description',
        expected: 'Fix bugs\t#1 first',
      );
    });

    test('leaves trailing whitespace outside the quotes', () async {
      final String fixed = await expectRoundTrip(
        ['description: Fix #1 now \t'],
        field: 'description',
        expected: 'Fix #1 now',
      );

      expect(fixed, contains("description: 'Fix #1 now' \t\n"));
    });

    test('quotes a multi-line value in place', () async {
      final String fixed = await expectRoundTrip(
        ['description: Fix bugs', "  that aren't triaged", '', '  from the tracker #123 first'],
        field: 'description',
        expected: "Fix bugs that aren't triaged\nfrom the tracker #123 first",
      );

      expect(
        fixed,
        contains(
          "description: 'Fix bugs\n  that aren''t triaged\n\n  from the tracker #123 first'\n",
        ),
      );
    });

    test('keeps CRLF line endings', () async {
      final String fixed = await expectRoundTrip(
        ['description: Fix bugs', '  from #123', 'license: MIT'],
        field: 'description',
        expected: 'Fix bugs from #123',
        lineEnding: '\r\n',
      );

      expect(
        fixed,
        _skillMd(["description: 'Fix bugs", "  from #123'", 'license: MIT'], lineEnding: '\r\n'),
      );
    });

    test('quotes nested values, list items and flow collections', () async {
      final String fixed = await _fixClean(
        _skillMd([
          'description: Fix #1 first',
          'compatibility: Needs git #2',
          'metadata:',
          '  short-description: Run the #1 check',
          '  tags:',
          '    - triage #bugs',
          '  flow: { a: Run #1',
          // The comment drops the `, z` too, so the fix keeps it in the item.
          '    , b: [x #y, z',
          '    ] }',
        ]),
      );

      final YamlMap yaml = _frontmatter(fixed);
      expect(yaml['description'], 'Fix #1 first');
      expect(yaml['compatibility'], 'Needs git #2');
      final metadata = yaml['metadata'] as YamlMap;
      expect(metadata['short-description'], 'Run the #1 check');
      expect(metadata['tags'], ['triage #bugs']);
      expect(metadata['flow'], {
        'a': 'Run #1',
        'b': ['x #y, z'],
      });
    });

    test('keeps an anchor outside the quotes', () async {
      final String fixed = await _fixClean(
        _skillMd(['description: &d Fix #1 now', 'compatibility: *d']),
      );

      expect(_frontmatter(fixed)['compatibility'], 'Fix #1 now');
    });

    test('quotes the value, not the tag or anchor, when they are alone on the key line', () async {
      final String fixed = await _fixClean(
        _skillMd([
          'description: Fix #1 first',
          'metadata:',
          '  tagged: !!str',
          '    Fix it #12 now',
          '  anchored: &a',
          '    Run #3 too',
          '  alias: *a',
        ]),
      );

      final metadata = _frontmatter(fixed)['metadata'] as YamlMap;
      expect(metadata['tagged'], 'Fix it #12 now');
      expect(metadata['anchored'], 'Run #3 too');
      expect(metadata['alias'], 'Run #3 too');
    });

    test('pulls a deliberate comment into the value', () async {
      // The rule can't tell a deliberate comment from lost text, so --fix
      // keeps the text. RULES.md tells authors to move such a comment first.
      await expectRoundTrip(
        ['description: Triage bugs. # TODO reword'],
        field: 'description',
        expected: 'Triage bugs. # TODO reword',
      );
    });

    test('leaves findings with an ignored subject unchanged', () async {
      final String content = _skillMd(['description: Fix #1 now', 'compatibility: Needs git #2']);

      final String fixed = await _rule.fix(_context(content), ignoredSubjects: {'compatibility'});

      expect(fixed, _skillMd(["description: 'Fix #1 now'", 'compatibility: Needs git #2']));
    });

    test('returns the content unchanged when there is nothing to fix', () async {
      final String content = _skillMd(["description: 'Fix #1 now'", 'license: MIT # see LICENSE']);
      const withoutFrontmatter = 'Fix #1 now\n';

      expect(
        await _rule.fix(_context(_skillMd(['description: Fine.']))),
        _skillMd(['description: Fine.']),
      );
      expect(await _rule.fix(_context(content), ignoredSubjects: {'license'}), content);
      expect(await _rule.fix(_context(withoutFrontmatter)), withoutFrontmatter);
    });

    test('is idempotent', () async {
      final String once = await _fixClean(_skillMd(['description: Fix #1 now']));

      expect(await _rule.fix(_context(once)), once);
    });
  });

  defineCliTests();
}

/// Defines the tests that start the CLI. [main] calls this, and
/// `compiled_test/cli_test.dart` calls it again to run the same tests
/// against the compiled binary.
void defineCliTests() {
  group('frontmatter-truncated-by-comment CLI', () {
    const truncated = 'description: Use when asked "fix #123" or to triage bugs.';

    Future<File> writeSkill(Directory tempDir) async {
      final Directory skillDir = await Directory(p.join(tempDir.path, 'my-skill')).create();
      final file = File(p.join(skillDir.path, 'SKILL.md'));
      await file.writeAsString(_skillMd([truncated]));
      return file;
    }

    test('passes when the rule is not enabled', () async {
      await withTempDir((tempDir) async {
        final File skill = await writeSkill(tempDir);
        final TestProcess process = await startCli(['--ignore-config', '-s', skill.parent.path]);
        await process.shouldExit(0);
      });
    });

    test('fails with the flag and reports the dropped text', () async {
      await withTempDir((tempDir) async {
        final File skill = await writeSkill(tempDir);
        final TestProcess process = await startCli([
          '--ignore-config',
          '-s',
          skill.parent.path,
          '--frontmatter-truncated-by-comment',
        ]);
        final String output = (await process.stderr.rest.toList()).join('\n');
        await process.shouldExit(1);
        expect(output, contains('drops "#123" or to triage bugs."'));
      });
    });

    test('--fix quotes the value so the skill passes', () async {
      await withTempDir((tempDir) async {
        final File skill = await writeSkill(tempDir);
        final TestProcess process = await startCli([
          '--ignore-config',
          '-s',
          skill.parent.path,
          '--frontmatter-truncated-by-comment',
          '--fix',
        ]);
        await process.shouldExit(0);
        expect(
          _frontmatter(await skill.readAsString())['description'],
          'Use when asked "fix #123" or to triage bugs.',
        );
      });
    });
  });
}
