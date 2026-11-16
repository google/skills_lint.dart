// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Every finding of a registered rule has a `region`, unless the rule is
/// listed in `_rulesWithoutRegion` with the reason.
///
/// Why this matters:
/// - Text output can name only the file, but JSON and SARIF need a line.
///   Code scanning and editors drop or misplace a finding without one.
/// - A new rule can forget `region:` and every rule test still passes,
///   because each rule test checks only its own messages.
///
/// Revisit this if a machine output format stops reporting lines, or if
/// many rules turn out to have findings with nothing to point at.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_lint/src/config_parser.dart';
import 'package:skills_lint/src/models/analysis_severity.dart';
import 'package:skills_lint/src/models/output_format.dart';
import 'package:skills_lint/src/models/rule_config.dart';
import 'package:skills_lint/src/models/validation_error.dart';
import 'package:skills_lint/src/pub_archive_loader.dart';
import 'package:skills_lint/src/rule_registry.dart';
import 'package:skills_lint/src/rules/description_length_rule.dart';
import 'package:skills_lint/src/rules/path_does_not_exist_rule.dart';
import 'package:skills_lint/src/rules/valid_yaml_metadata_rule.dart';
import 'package:skills_lint/src/validation_session.dart';
import 'package:tar/tar.dart' show TarEntry, tarWriter;
import 'package:test/test.dart';

/// Rules whose findings have no line to point at, with the reason.
const Map<String, String> _rulesWithoutRegion = {
  PathDoesNotExistRule.ruleName:
      'The finding is about a missing directory or SKILL.md, so there is no file to point into.',
};

void main() {
  test('exempts only registered rules from reporting a region', () {
    expect(RuleRegistry.ruleNames, containsAll(_rulesWithoutRegion.keys));
  });

  test('every registered rule reports a region, unless it is exempt', () async {
    final List<ValidationError> errors = await _validateFixture();

    expect(
      {for (final error in errors) error.ruleId},
      RuleRegistry.ruleNames.toSet(),
      reason: 'Make the fixture in rule_region_convention_test.dart trigger every registered rule.',
    );
    for (final error in errors) {
      if (_rulesWithoutRegion.containsKey(error.ruleId)) {
        expect(
          error.region,
          isNull,
          reason: '${error.ruleId} reports a region. Remove it from _rulesWithoutRegion.',
        );
      } else {
        expect(
          error.region,
          isNotNull,
          reason:
              '${error.ruleId} reports no region, so JSON and SARIF cannot point at a line. '
              'Pass `region:` to ValidationError.',
        );
      }
    }
  });
}

/// Validates, with every registered rule turned on, a package with two
/// skills that between them break every rule, and returns the findings.
Future<List<ValidationError>> _validateFixture() async {
  final Directory packageDir = await Directory.systemTemp.createTemp(
    'rule_region_convention_test.',
  );
  addTearDown(() => packageDir.delete(recursive: true));
  await File(p.join(packageDir.path, 'pubspec.yaml')).writeAsString('name: my_pkg\n');
  final skillsDir = Directory(p.join(packageDir.path, 'skills'));
  // No SKILL.md, for path-does-not-exist.
  await Directory(p.join(skillsDir.path, 'my-pkg-empty')).create(recursive: true);
  final String absoluteLink = p.join(skillsDir.path, 'bad', 'SKILL.md');
  // Not prefixed with the package name, for published-skill-name.
  final badDir = Directory(p.join(skillsDir.path, 'bad'));
  await badDir.create(recursive: true);
  await File(p.join(badDir.path, 'SKILL.md')).writeAsString(
    '---\n'
    // Not the directory name, for invalid-skill-name.
    'name: Bad\n'
    'description: ${'x' * (DescriptionLengthRule.maxDescriptionLength + 1)}\n'
    'compatibility: ${'x' * (ValidYamlMetadataRule.maxCompatibilityLength + 1)}\n'
    'owner: me\n'
    // No `metadata: internal: true`, for prevent-skills-sh-publishing.
    '---\n'
    '\n'
    'This line ends in a space. \n'
    '- [Missing](references/missing.md)\n'
    '- [Absolute]($absoluteLink)\n',
  );

  final session = ValidationSession(
    config: const Configuration(),
    resolvedRuleConfigs: {
      for (final String rule in RuleRegistry.ruleNames)
        rule: const RuleConfigPatch(severity: AnalysisSeverity.error),
    },
    ignoreFileOverride: null,
    customRules: const [],
    printWarnings: true,
    fastFail: false,
    quiet: true,
    generateBaseline: false,
    fix: false,
    fixApply: false,
    // The JSON reporter writes only when the session completes, so the test
    // prints nothing.
    format: OutputFormat.json,
    // The archive leaves out bad/SKILL.md, for pub-archive-includes-skill.
    pubArchiveLoader: PubArchiveLoader(runProcess: _publishEmptyArchive),
  );
  await session.processSkillRoot(skillsDir.path);
  return [for (final result in session.results) ...result.validationErrors];
}

/// Stands in for `dart pub publish --to-archive` and writes an archive with
/// no files in it.
Future<ProcessResult> _publishEmptyArchive(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) async {
  const toArchiveOption = '--to-archive=';
  final String archivePath = arguments
      .firstWhere((String argument) => argument.startsWith(toArchiveOption))
      .substring(toArchiveOption.length);
  await const Stream<TarEntry>.empty()
      .transform(tarWriter)
      .transform(gzip.encoder)
      .pipe(File(archivePath).openWrite());
  return ProcessResult(0, 0, '', '');
}
