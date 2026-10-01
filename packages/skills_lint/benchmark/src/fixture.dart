// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Writes deterministic synthetic skill repositories for the benchmarks.
library;

import 'dart:io';
import 'dart:math';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// The shape of a generated skills repository.
@immutable
final class FixtureSpec {
  const FixtureSpec({required this.skillCount, this.seed = defaultSeed, this.invalidEvery = 10});

  /// The seed that the benchmarks use. Changing it changes the workload.
  static const int defaultSeed = 23;

  /// Number of skill directories to write under `skills/`.
  final int skillCount;

  /// Seed for the pseudo-random content. The same seed and [skillCount]
  /// write the same files, apart from absolute paths that embed the
  /// fixture root.
  final int seed;

  /// Every [invalidEvery]th skill, starting with the first, has planted lint
  /// errors chosen by [invalidKindsFor]. Must be at least 1.
  final int invalidEvery;
}

/// A lint error that the generator plants in an invalid skill.
///
/// Each kind violates a different built-in rule, and together they violate
/// every built-in rule, so that every rule reports at least once.
enum InvalidKind {
  /// Frontmatter `name:` differs from the directory name
  /// (`invalid-skill-name`, fixable).
  nameMismatch,

  /// A body line ends in one space (`check-trailing-whitespace`, fixable).
  trailingWhitespace,

  /// A relative link names a missing file next to a near-miss sibling
  /// (`check-relative-paths`, which then searches for a suggestion).
  brokenRelativeLink,

  /// The description exceeds 1024 characters (`description-too-long`).
  descriptionTooLong,

  /// A link uses the absolute path of a file in the skill
  /// (`check-absolute-paths`, fixable).
  absoluteLink,

  /// The frontmatter has a field outside the specification
  /// (`disallowed-field`).
  disallowedField,

  /// `metadata: internal:` is `false` (`prevent-skills-sh-publishing`).
  notInternal,

  /// The skill name doesn't start with [fixturePackageName]
  /// (`published-skill-name`).
  unpublishedName,

  /// The `compatibility:` field exceeds 500 characters
  /// (`valid-yaml-metadata`).
  compatibilityTooLong,

  /// The skill directory has no `SKILL.md` (`path-does-not-exist`). The
  /// other rules have nothing to read, so this kind is never combined.
  missingSkillMd,
}

/// Returns the kinds planted in the [invalidIndex]th invalid skill.
///
/// Invalid skills cycle through [InvalidKind.values]. Each also gets the
/// next kind in the cycle, so that most invalid skills have two errors,
/// unless either kind is [InvalidKind.missingSkillMd].
Set<InvalidKind> invalidKindsFor(int invalidIndex) {
  const List<InvalidKind> kinds = InvalidKind.values;
  final InvalidKind first = kinds[invalidIndex % kinds.length];
  final InvalidKind second = kinds[(invalidIndex + 1) % kinds.length];
  if (first == InvalidKind.missingSkillMd || second == InvalidKind.missingSkillMd) {
    return {first};
  }
  return {first, second};
}

/// Counts of what [writeFixture] wrote.
@immutable
final class FixtureStats {
  const FixtureStats({
    required this.skillCount,
    required this.invalidSkillCount,
    required this.fileCount,
    required this.byteCount,
  });

  /// Number of skill directories.
  final int skillCount;

  /// Number of skills that carry a planted lint error.
  final int invalidSkillCount;

  /// Number of files written, including `skills_lint.yaml`.
  final int fileCount;

  /// Total length of the files written, in characters. The generator
  /// writes ASCII apart from fixture-root paths, so this is close to the
  /// size on disk.
  final int byteCount;
}

/// Name of the directory under the fixture root that holds the skills.
const String skillsDirectoryName = 'skills';

/// Package name that the fixture passes to `published-skill-name`.
///
/// Every generated skill name starts with `skill-`, apart from
/// [InvalidKind.unpublishedName] skills.
const String fixturePackageName = 'skill';

/// Contents of the `skills_lint.yaml` written at the fixture root.
///
/// It turns on every built-in rule, so each rule runs on every skill.
///
/// `published-skill-name` checks that each skill name starts with a
/// package name. Without `package_name`, the rule looks for a
/// `pubspec.yaml` in the skill directory and each parent directory, so its
/// result would depend on where the fixture is written: no `pubspec.yaml`
/// makes the rule report every skill, and a parent Dart package makes it
/// check against that package's name. Setting [fixturePackageName] keeps
/// the workload the same wherever the fixture is written.
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
      package_name: $fixturePackageName
  directories:
    - path: "$skillsDirectoryName"
''';

/// Writes a skills repository described by [spec] into [root].
///
/// [root] must be an empty or missing directory. The layout is
/// `root/skills_lint.yaml` plus one directory per skill under
/// `root/skills/`, each with a `SKILL.md` and optional `references/` and
/// `scripts/` files that the `SKILL.md` links to.
FixtureStats writeFixture(String root, FixtureSpec spec) {
  if (spec.invalidEvery < 1) {
    throw ArgumentError.value(spec.invalidEvery, 'invalidEvery', 'must be at least 1');
  }
  final writer = _FixtureWriter(root, Random(spec.seed));
  writer.write(p.join(root, 'skills_lint.yaml'), fixtureConfig);
  var invalid = 0;
  for (var i = 0; i < spec.skillCount; i++) {
    final Set<InvalidKind> kinds = i % spec.invalidEvery == 0
        ? invalidKindsFor(i ~/ spec.invalidEvery)
        : const {};
    if (kinds.isNotEmpty) {
      invalid++;
    }
    writer.writeSkill(i, kinds);
  }
  return FixtureStats(
    skillCount: spec.skillCount,
    invalidSkillCount: invalid,
    fileCount: writer.fileCount,
    byteCount: writer.byteCount,
  );
}

const List<String> _words = [
  'agent', 'analyze', 'build', 'cache', 'check', 'config', 'data', 'debug', //
  'deploy', 'docs', 'error', 'event', 'file', 'format', 'graph', 'guide',
  'index', 'input', 'layout', 'lint', 'log', 'model', 'module', 'network',
  'output', 'package', 'parse', 'path', 'plan', 'query', 'release', 'report',
  'review', 'route', 'schema', 'script', 'search', 'server', 'setup', 'source',
  'state', 'stream', 'style', 'task', 'test', 'token', 'trace', 'widget',
];

final class _FixtureWriter {
  _FixtureWriter(this.root, this.random);

  final String root;
  final Random random;
  int fileCount = 0;
  int byteCount = 0;

  void write(String path, String contents) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(contents);
    fileCount++;
    byteCount += contents.length;
  }

  void writeSkill(int index, Set<InvalidKind> kinds) {
    final String prefix = kinds.contains(InvalidKind.unpublishedName) ? 'tool' : fixturePackageName;
    final dirName = '$prefix-${index.toString().padLeft(4, '0')}-${_word()}-${_word()}';
    final String dir = p.join(root, skillsDirectoryName, dirName);
    final List<String> references = [
      for (var r = random.nextInt(4); r > 0; r--) 'references/${_word()}-$r.md',
    ];
    final List<String> scripts = [
      for (var s = random.nextInt(3); s > 0; s--) 'scripts/${_word()}-$s.sh',
    ];
    // The absolute link needs a file to point at, and the broken link needs
    // a near-miss sibling for the suggestion search to find. A skill without
    // a SKILL.md still needs one file so that its directory exists.
    if (references.isEmpty &&
        (kinds.contains(InvalidKind.absoluteLink) ||
            kinds.contains(InvalidKind.brokenRelativeLink) ||
            kinds.contains(InvalidKind.missingSkillMd))) {
      references.add('references/${_word()}-1.md');
    }
    for (final ref in references) {
      write(p.join(dir, ref), _markdown(3 + random.nextInt(20)));
    }
    for (final script in scripts) {
      write(p.join(dir, script), '#!/usr/bin/env bash\nset -euo pipefail\necho "${_sentence()}"\n');
    }
    if (!kinds.contains(InvalidKind.missingSkillMd)) {
      write(p.join(dir, 'SKILL.md'), _skillMd(dir, dirName, references, scripts, kinds));
    }
  }

  String _skillMd(
    String dir,
    String dirName,
    List<String> references,
    List<String> scripts,
    Set<InvalidKind> kinds,
  ) {
    final name = kinds.contains(InvalidKind.nameMismatch) ? '$dirName-renamed' : dirName;
    final String description = kinds.contains(InvalidKind.descriptionTooLong)
        ? _words.join(' ') * 4
        : _paragraph(1 + random.nextInt(6));
    final buffer = StringBuffer()
      ..writeln('---')
      ..writeln('name: $name')
      ..writeln('description: >-')
      ..writeln('  $description');
    _writeOptionalFields(buffer, kinds);
    buffer
      ..writeln('metadata:')
      ..writeln('  internal: ${!kinds.contains(InvalidKind.notInternal)}')
      ..writeln('---')
      ..writeln()
      ..writeln('# ${_sentence()}')
      ..writeln()
      ..write(_markdown(2 + random.nextInt(12)));
    _writeLinks(buffer, dir, references, scripts, kinds);
    if (kinds.contains(InvalidKind.trailingWhitespace)) {
      buffer.writeln('${_sentence()} ');
    }
    return buffer.toString();
  }

  void _writeOptionalFields(StringBuffer buffer, Set<InvalidKind> kinds) {
    if (random.nextBool()) {
      buffer.writeln('license: Apache-2.0');
    }
    if (kinds.contains(InvalidKind.compatibilityTooLong)) {
      buffer.writeln('compatibility: ${_words.join(' ') * 2}');
    } else if (random.nextInt(4) == 0) {
      buffer.writeln('compatibility: ${_sentence()}');
    }
    if (random.nextInt(3) == 0) {
      buffer.writeln('allowed-tools: Bash Read Write');
    }
    if (kinds.contains(InvalidKind.disallowedField)) {
      buffer.writeln('owner: ${_word()}');
    }
  }

  void _writeLinks(
    StringBuffer buffer,
    String dir,
    List<String> references,
    List<String> scripts,
    Set<InvalidKind> kinds,
  ) {
    buffer
      ..writeln()
      ..writeln('## Resources')
      ..writeln();
    for (final target in [...references, ...scripts]) {
      buffer.writeln('- [${p.url.basename(target)}]($target): ${_sentence()}');
    }
    buffer.writeln('- [Specification](https://agentskills.io/specification)');
    if (kinds.contains(InvalidKind.brokenRelativeLink)) {
      final String existing = references.first;
      buffer.writeln('- [Missing](${existing.replaceFirst('.md', 's.md')})');
    }
    if (kinds.contains(InvalidKind.absoluteLink)) {
      buffer.writeln('- [Absolute](${p.join(dir, p.joinAll(p.url.split(references.first)))})');
    }
  }

  /// Returns [sections] Markdown sections of prose, lists and code.
  String _markdown(int sections) {
    final buffer = StringBuffer();
    for (var s = 0; s < sections; s++) {
      buffer
        ..writeln('## ${_sentence()}')
        ..writeln()
        ..writeln(_paragraph(2 + random.nextInt(4)))
        ..writeln();
      for (int item = random.nextInt(5); item > 0; item--) {
        buffer.writeln('- ${_sentence()}');
      }
      if (random.nextInt(3) == 0) {
        buffer
          ..writeln()
          ..writeln('```bash')
          ..writeln('dart run ${_word()} --${_word()}')
          ..writeln('```');
      }
      buffer.writeln();
    }
    return buffer.toString();
  }

  String _paragraph(int sentences) => [for (var i = 0; i < sentences; i++) _sentence()].join(' ');

  String _sentence() {
    final String words = [for (var i = 4 + random.nextInt(10); i > 0; i--) _word()].join(' ');
    return '${words[0].toUpperCase()}${words.substring(1)}.';
  }

  String _word() => _words[random.nextInt(_words.length)];
}
