// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Writes the skills repository that the benchmarks validate.
///
/// The repository is generated rather than checked in, because the CLI's
/// walk over 1000 skill directories is part of what the benchmarks measure.
/// Each skill is a copy of a template in `benchmark/fixture_templates/`.
///
/// The first skill always has planted violations, so the CLI exits with 1
/// on the fixture. `expectedExitCode` in `suite.dart` relies on this.
///
/// Changing the templates, [violations] or [plantedViolations] changes the
/// workload, so rename the benchmark in `suite.dart` when you change them.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// Name of the directory under the fixture root that holds the skills.
const String skillsDirectoryName = 'skills';

/// Directory of the templates, relative to `packages/skills_lint`.
final String templatesDirectory = p.join('benchmark', 'fixture_templates');

/// Package name that the fixture passes to `published-skill-name`.
const String fixturePackageName = 'skill';

/// Contents of the `skills_lint.yaml` written at the fixture root. It turns
/// on every built-in rule.
const String fixtureConfig =
    '''
skills_lint:
  rules:
    check-relative-paths: error
    check-absolute-paths: error
    check-trailing-whitespace: error
    disallowed-field: error
    prevent-skills-sh-publishing: error
    published-skill-name:
      severity: error
      # Without package_name, the rule looks for a pubspec.yaml above each
      # skill, so its result would depend on where the fixture is written.
      package_name: $fixturePackageName
  directories:
    - path: "$skillsDirectoryName"
''';

/// Every [invalidEvery]th skill, starting with the first, has violations.
const int invalidEvery = 10;

/// Longest description that `description-too-long` allows.
const int maxDescriptionLength = 1024;

/// Longest `compatibility:` value that `valid-yaml-metadata` allows.
const int maxCompatibilityLength = 500;

/// A change to a valid skill that makes one rule report.
typedef SkillEdit = void Function(FixtureSkill skill);

/// One edit for each built-in rule, keyed by rule ID.
///
/// `fixture_test.dart` checks that the keys are the registered rules.
final Map<String, SkillEdit> violations = {
  'invalid-skill-name': (s) => s.name = '${s.name}-renamed',
  'check-trailing-whitespace': (s) => s.bodySuffix = 'This line ends in a space. \n',
  'description-too-long': (s) => s.description = 'x' * (maxDescriptionLength + 1),
  'valid-yaml-metadata': (s) => s.fields['compatibility'] = 'x' * (maxCompatibilityLength + 1),
  'disallowed-field': (s) => s.fields['owner'] = 'benchmarks',
  'prevent-skills-sh-publishing': (s) => s.internal = false,
  'published-skill-name': (s) => s
    ..directoryName = 'tool-${s.directoryName}'
    ..name = 'tool-${s.name}',
  // A near miss of a real file, so that the rule also runs its search for
  // a suggestion.
  'check-relative-paths': (s) =>
      s.relativeLinks.add(s.template.firstReference.replaceFirst('.md', 's.md')),
  'check-absolute-paths': (s) => s.absoluteLinks.add(s.template.firstReference),
  'path-does-not-exist': (s) => s.omitSkillMd = true,
};

/// The rule IDs whose [violations] each invalid skill gets. Invalid skills
/// take the entries in turn.
///
/// Most entries have two rules, so that some skills report more than one
/// error. `path-does-not-exist` stands alone, because without a `SKILL.md`
/// no other rule runs.
const List<List<String>> plantedViolations = [
  ['invalid-skill-name', 'check-trailing-whitespace'],
  ['check-relative-paths', 'description-too-long'],
  ['check-absolute-paths', 'disallowed-field'],
  ['prevent-skills-sh-publishing', 'published-skill-name'],
  ['valid-yaml-metadata', 'check-relative-paths'],
  ['path-does-not-exist'],
];

/// A checked-in skill that the fixture copies.
final class SkillTemplate {
  SkillTemplate({required this.name, required this.body, required this.files});

  /// Reads the template in [directory]: `body.md` is the `SKILL.md` body,
  /// and every other file is copied as is.
  factory SkillTemplate.read(Directory directory) {
    final files = <String, String>{};
    for (final File file in directory.listSync(recursive: true).whereType<File>()) {
      final String path = p.split(p.relative(file.path, from: directory.path)).join('/');
      if (path != 'body.md') {
        files[path] = file.readAsStringSync();
      }
    }
    return SkillTemplate(
      name: p.basename(directory.path),
      body: File(p.join(directory.path, 'body.md')).readAsStringSync(),
      files: Map.fromEntries(files.entries.toList()..sort((a, b) => a.key.compareTo(b.key))),
    );
  }

  /// Directory name of the template, such as `small`.
  final String name;

  /// The Markdown below the frontmatter.
  final String body;

  /// Files next to `SKILL.md`, keyed by `/`-separated relative path.
  final Map<String, String> files;

  /// The first file under `references/`. Every template has one.
  String get firstReference => files.keys.firstWhere((path) => path.startsWith('references/'));
}

/// Reads the templates in [directory], sorted by name.
List<SkillTemplate> readTemplates([String? directory]) {
  final List<Directory> dirs = Directory(
    directory ?? templatesDirectory,
  ).listSync().whereType<Directory>().toList()..sort((a, b) => a.path.compareTo(b.path));
  return [for (final dir in dirs) SkillTemplate.read(dir)];
}

/// One generated skill, before it is written.
final class FixtureSkill {
  FixtureSkill(this.template, this.directoryName)
    : name = directoryName,
      description = 'Benchmark fixture skill copied from the ${template.name} template.';

  /// The template whose body and files this skill copies.
  final SkillTemplate template;

  /// Name of the skill directory.
  String directoryName;

  /// Frontmatter `name:`.
  String name;

  /// Frontmatter `description:`.
  String description;

  /// Frontmatter `metadata: internal:`.
  bool internal = true;

  /// Other frontmatter fields, written in insertion order.
  final Map<String, String> fields = {};

  /// Extra links, relative to the skill directory, added to the body.
  final List<String> relativeLinks = [];

  /// Extra links, relative to the skill directory, that the body writes as
  /// absolute paths.
  final List<String> absoluteLinks = [];

  /// Text appended to the body.
  String bodySuffix = '';

  /// Whether to leave out `SKILL.md`.
  bool omitSkillMd = false;
}

/// Returns the skill at [index], with its violations applied.
FixtureSkill fixtureSkill(int index, List<SkillTemplate> templates) {
  final skill = FixtureSkill(
    templates[index % templates.length],
    '$fixturePackageName-${index.toString().padLeft(4, '0')}',
  );
  if (index % invalidEvery == 0) {
    final List<String> rules =
        plantedViolations[(index ~/ invalidEvery) % plantedViolations.length];
    for (final rule in rules) {
      violations[rule]!(skill);
    }
  }
  return skill;
}

/// Returns the `SKILL.md` of [skill], whose directory is [skillDirectory].
String renderSkillMd(FixtureSkill skill, String skillDirectory) {
  final buffer = StringBuffer()
    ..writeln('---')
    ..writeln('name: ${skill.name}')
    ..writeln('description: ${skill.description}');
  for (final MapEntry(:key, :value) in skill.fields.entries) {
    buffer.writeln('$key: $value');
  }
  buffer
    ..writeln('metadata:')
    ..writeln('  internal: ${skill.internal}')
    ..writeln('---')
    ..writeln()
    ..write(skill.template.body);
  for (final String link in skill.relativeLinks) {
    buffer.writeln('- [Link]($link)');
  }
  for (final String link in skill.absoluteLinks) {
    // Links use `/`; the absolute path uses the host separator, so that it
    // is a real path on Windows too.
    buffer.writeln('- [Link](${p.join(skillDirectory, p.joinAll(p.url.split(link)))})');
  }
  buffer.write(skill.bodySuffix);
  return buffer.toString();
}

/// Writes `skills_lint.yaml` and [skillCount] skills into [root], which must
/// be empty or missing.
void writeFixture(String root, int skillCount, {List<SkillTemplate>? templates}) {
  final List<SkillTemplate> sources = templates ?? readTemplates();
  _write(p.join(root, 'skills_lint.yaml'), fixtureConfig);
  for (var i = 0; i < skillCount; i++) {
    final FixtureSkill skill = fixtureSkill(i, sources);
    final String dir = p.join(root, skillsDirectoryName, skill.directoryName);
    for (final MapEntry(key: path, value: contents) in skill.template.files.entries) {
      _write(p.join(dir, p.joinAll(p.url.split(path))), contents);
    }
    if (!skill.omitSkillMd) {
      _write(p.join(dir, 'SKILL.md'), renderSkillMd(skill, dir));
    }
  }
}

void _write(String path, String contents) {
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(contents);
}
