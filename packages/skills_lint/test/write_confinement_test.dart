// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Tests that `--fix`, `--generate-baseline` and ignore-file creation write
/// only inside the directories skills_lint scans, after symlinks are
/// resolved.
///
/// Each group builds a repository with real files next to an `outside`
/// directory, runs the CLI in the repository, and checks that the files in
/// `outside` are unchanged, that the run fails, and that stderr names the
/// refused path. Matching tests show that a path named on the command line
/// is still written.
///
/// The symlink tests run on every OS. On Windows they fail, rather than
/// skip, when the runner can't create a symlink, so CI can't pass without
/// running them.
library;

import 'dart:io';

import 'package:io/io.dart' show ExitCode;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:test_process/test_process.dart';

import 'test_utils.dart';

/// A `SKILL.md` whose `name` doesn't match its directory, which `--fix`
/// rewrites.
String _skillNamed(String name) => buildFrontmatter(name: name);

void main() => defineCliTests();

/// Defines the tests, which `compiled_test/` also runs against the compiled CLI.
void defineCliTests() {
  late Directory repo;
  late Directory outside;

  setUp(() async {
    final temp = Directory(
      (await Directory.systemTemp.createTemp('write_confinement_test.')).resolveSymbolicLinksSync(),
    );
    addTearDown(() => temp.delete(recursive: true));
    repo = Directory(p.join(temp.path, 'repo'))..createSync();
    outside = Directory(p.join(temp.path, 'outside'))..createSync();
  });

  /// Runs the CLI with [arguments] in [repo], expects [exitCode], and returns
  /// stderr.
  Future<String> run(List<String> arguments, {required int exitCode}) async {
    final TestProcess process = await startCli(arguments, workingDirectory: repo.path);
    final String stdout = (await process.stdout.rest.toList()).join('\n');
    final String stderr = (await process.stderr.rest.toList()).join('\n');
    printOnFailure('skills_lint ${arguments.join(' ')}\nstdout:\n$stdout\nstderr:\n$stderr');
    await process.shouldExit(exitCode);
    return stderr;
  }

  /// Writes `skills_lint.yaml` into [repo] with one entry under
  /// `directories`, whose lines are [entry].
  void writeConfig(List<String> entry) => File(
    p.join(repo.path, 'skills_lint.yaml'),
  ).writeAsStringSync('skills_lint:\n  directories:\n${entry.map((l) => '    $l\n').join()}');

  /// Matches stderr that says skills_lint did not write [path].
  Matcher refused(String path) => allOf(contains('Error: did not '), contains(path));

  group('symlinks', () {
    test('--fix does not write a skill that a symlinked directory points to', () async {
      final Directory real = await createDummySkill(
        outside,
        name: 'real',
        skillContent: _skillNamed('real'),
      );
      final skills = Directory(p.join(repo.path, 'skills'))..createSync();
      // Fails, rather than skips, where symlinks can't be created.
      Link(p.join(skills.path, 'evil')).createSync(real.path);

      final String stderr = await run(['--fix', '-d', 'skills'], exitCode: 1);

      expect(File(p.join(real.path, 'SKILL.md')).readAsStringSync(), _skillNamed('real'));
      expect(stderr, refused(p.join(skills.path, 'evil', 'SKILL.md')));
      expect(stderr, contains("resolves to '${p.join(real.path, 'SKILL.md')}'"));
    });

    test('--fix does not write the file that a symlinked SKILL.md points to', () async {
      final victim = File(p.join(outside.path, 'victim.md'))
        ..writeAsStringSync(_skillNamed('victim'));
      final skill = Directory(p.join(repo.path, 'skills', 'foo'))..createSync(recursive: true);
      Link(p.join(skill.path, 'SKILL.md')).createSync(victim.path);

      final String stderr = await run(['--fix', '-d', 'skills'], exitCode: 1);

      expect(victim.readAsStringSync(), _skillNamed('victim'));
      expect(stderr, refused(p.join(skill.path, 'SKILL.md')));
    });

    test('--fix writes a skill whose real directory is named with -s', () async {
      final Directory real = await createDummySkill(
        outside,
        name: 'real',
        skillContent: _skillNamed('wrong'),
      );

      await run(['--fix', '-s', real.path], exitCode: 0);

      expect(File(p.join(real.path, 'SKILL.md')).readAsStringSync(), _skillNamed('real'));
    });

    test('--generate-baseline does not write through a symlinked ignore file', () async {
      final victim = File(p.join(outside.path, 'victim.json'))..writeAsStringSync('precious');
      final skills = Directory(p.join(repo.path, 'skills'))..createSync();
      await createDummySkill(skills, name: 'foo', skillContent: _skillNamed('bar'));
      final String ignoreFile = p.join(skills.path, 'skills_lint_ignore.json');
      Link(ignoreFile).createSync(victim.path);

      final String stderr = await run(['--generate-baseline', '-d', 'skills'], exitCode: 1);

      expect(victim.readAsStringSync(), 'precious');
      expect(stderr, refused(ignoreFile));
    });

    test('--fix passes for a symlinked skill that needs no fixes', () async {
      final Directory real = await createDummySkill(
        outside,
        name: 'evil',
        skillContent: _skillNamed('evil'),
      );
      final skills = Directory(p.join(repo.path, 'skills'))..createSync();
      Link(p.join(skills.path, 'evil')).createSync(real.path);

      await run(['--fix', '-d', 'skills'], exitCode: 0);
    });

    test('validation does not create an ignore_file through a link followed by ..', () async {
      final deep = Directory(p.join(outside.path, 'far', 'deep'))..createSync(recursive: true);
      Directory(p.join(outside.path, 'far', 'vdir')).createSync();
      Link(p.join(repo.path, 'l')).createSync(deep.path);
      // Create `vdir` before `sub` so Windows creates a directory symlink;
      // `sub` resolves to `outside/far/vdir`, though `l/..` reads as `repo`.
      Link(p.join(repo.path, 'sub')).createSync(p.join('l', '..', 'vdir'));
      await createDummySkill(
        Directory(p.join(repo.path, 'skills')),
        name: 'foo',
        skillContent: _skillNamed('foo'),
      );
      writeConfig(['- path: skills', '  ignore_file: sub/created.json']);

      final String stderr = await run([], exitCode: 1);

      final String created = p.join(outside.path, 'far', 'vdir', 'created.json');
      expect(File(created).existsSync(), isFalse, reason: '$created was created');
      expect(stderr, refused(p.join(repo.path, 'sub', 'created.json')));
    });

    test('--generate-baseline does not create the target of a dangling symlink', () async {
      final String target = p.join(outside.path, 'created.json');
      final skills = Directory(p.join(repo.path, 'skills'))..createSync();
      await createDummySkill(skills, name: 'foo', skillContent: _skillNamed('bar'));
      Link(p.join(skills.path, 'skills_lint_ignore.json')).createSync(target);

      await run(['--generate-baseline', '-d', 'skills'], exitCode: 1);

      expect(File(target).existsSync(), isFalse, reason: '$target was created');
    });
  });

  group('skills_lint.yaml', () {
    test('--fix does not write skills in a directory outside the configuration', () async {
      final skills = Directory(p.join(outside.path, 'skills'))..createSync();
      final Directory skill = await createDummySkill(
        skills,
        name: 'foo',
        skillContent: _skillNamed('bar'),
      );
      writeConfig(['- path: ${_yamlString(skills.path)}']);

      final String stderr = await run(['--fix'], exitCode: 1);

      expect(File(p.join(skill.path, 'SKILL.md')).readAsStringSync(), _skillNamed('bar'));
      expect(stderr, refused(p.join(skill.path, 'SKILL.md')));
    });

    test('--fix writes the same skills when the directory is named with -d', () async {
      final skills = Directory(p.join(outside.path, 'skills'))..createSync();
      final Directory skill = await createDummySkill(
        skills,
        name: 'foo',
        skillContent: _skillNamed('bar'),
      );

      await run(['--fix', '-d', skills.path], exitCode: 0);

      expect(File(p.join(skill.path, 'SKILL.md')).readAsStringSync(), _skillNamed('foo'));
      // The fixed skill validates cleanly.
      await run(['-d', skills.path], exitCode: 0);
    });

    test('--generate-baseline does not replace an ignore_file outside the configuration', () async {
      final victim = File(p.join(outside.path, 'victim.json'))..writeAsStringSync('precious');
      await createDummySkill(
        Directory(p.join(repo.path, 'skills')),
        name: 'foo',
        skillContent: _skillNamed('bar'),
      );
      writeConfig(['- path: skills', '  ignore_file: ${_yamlString(victim.path)}']);

      final String stderr = await run(['--generate-baseline'], exitCode: 1);

      expect(victim.readAsStringSync(), 'precious');
      expect(stderr, refused(victim.path));
    });

    test('validation does not create a missing ignore_file outside the configuration', () async {
      final String victim = p.join(outside.path, 'created.json');
      await createDummySkill(
        Directory(p.join(repo.path, 'skills')),
        name: 'foo',
        skillContent: _skillNamed('foo'),
      );
      writeConfig(['- path: skills', '  ignore_file: ${_yamlString(victim)}']);

      final String stderr = await run([], exitCode: 1);

      expect(File(victim).existsSync(), isFalse, reason: '$victim was created');
      expect(stderr, refused(victim));
    });

    test(
      'individual_skills: [path: .] does not widen the boundary to the parent of skills_lint.yaml',
      () async {
        final victim = File(p.join(outside.path, 'victim.md'))
          ..writeAsStringSync('${_skillNamed('repo')}Trailing space \n');
        Link(p.join(repo.path, 'SKILL.md')).createSync(victim.path);
        File(p.join(repo.path, 'skills_lint.yaml')).writeAsStringSync(
          'skills_lint:\n'
          '  individual_skills:\n'
          '    - path: .\n'
          '      rules:\n'
          '        check-trailing-whitespace: error\n',
        );

        final String stderr = await run(['--fix'], exitCode: 1);

        expect(victim.readAsStringSync(), '${_skillNamed('repo')}Trailing space \n');
        expect(stderr, refused(p.join(repo.path, 'SKILL.md')));
      },
    );

    test('--generate-baseline writes an ignore file named with --ignore-file', () async {
      final String ignoreFile = p.join(outside.path, 'baseline.json');
      await createDummySkill(
        Directory(p.join(repo.path, 'skills')),
        name: 'foo',
        skillContent: _skillNamed('bar'),
      );

      await run(['--generate-baseline', '-d', 'skills', '--ignore-file', ignoreFile], exitCode: 0);

      expect(File(ignoreFile).readAsStringSync(), contains('"foo"'));
      // The baseline covers the finding it was generated from.
      await run(['-d', 'skills', '--ignore-file', ignoreFile], exitCode: 0);
    });
  });

  group('write_allow and --allow-write', () {
    /// Links `skills/foo` to `vendor/foo`, a skill in [repo] that `--fix`
    /// renames in its frontmatter, and returns the real `SKILL.md`.
    File vendoredSkill() {
      final vendor = Directory(p.join(repo.path, 'vendor'))..createSync();
      final skills = Directory(p.join(repo.path, 'skills'))..createSync();
      final skill = Directory(p.join(vendor.path, 'foo'))..createSync();
      Link(p.join(skills.path, 'foo')).createSync(skill.path);
      return File(p.join(skill.path, 'SKILL.md'))..writeAsStringSync(_skillNamed('bar'));
    }

    test('--fix refuses a symlinked skill in another folder of the repository', () async {
      final File skillMd = vendoredSkill();
      writeConfig(['- path: skills']);

      final String stderr = await run(['--fix'], exitCode: 1);

      expect(skillMd.readAsStringSync(), _skillNamed('bar'));
      expect(stderr, contains('write_allow'));
    });

    test('write_allow lets --fix write a symlinked skill in that folder', () async {
      final File skillMd = vendoredSkill();
      writeConfig(['- path: skills', '  write_allow: [vendor]']);

      await run(['--fix'], exitCode: 0);

      expect(skillMd.readAsStringSync(), _skillNamed('foo'));
      // The fixed skill validates cleanly.
      await run([], exitCode: 0);
    });

    test('--allow-write lets --fix write a symlinked skill in that folder', () async {
      final File skillMd = vendoredSkill();

      await run(['--fix', '-d', 'skills', '--allow-write', 'vendor'], exitCode: 0);

      expect(skillMd.readAsStringSync(), _skillNamed('foo'));
    });

    test('write_allow does not turn on a fix that fix: false turns off', () async {
      final File skillMd = vendoredSkill();
      writeConfig([
        '- path: skills',
        '  write_allow: [vendor]',
        '  rules:',
        '    invalid-skill-name: {fix: false}',
      ]);

      await run(['--fix'], exitCode: 1);

      expect(skillMd.readAsStringSync(), _skillNamed('bar'));
    });

    test('a write_allow directory outside the configuration is a configuration error', () async {
      vendoredSkill();
      writeConfig(['- path: skills', '  write_allow: [${_yamlString(outside.path)}]']);

      final String stderr = await run(['--fix'], exitCode: ExitCode.config.code);

      expect(stderr, contains('Configuration error'));
      expect(stderr, contains('"write_allow" for "skills" has "${outside.path}"'));
    });

    test('a write_allow symlink outside the configuration is a configuration error', () async {
      final skills = Directory(p.join(outside.path, 'skills'))..createSync();
      final Directory skill = await createDummySkill(
        skills,
        name: 'foo',
        skillContent: _skillNamed('bar'),
      );
      Link(p.join(repo.path, 'escape')).createSync(skills.path);
      final local = Directory(p.join(repo.path, 'skills'))..createSync();
      Link(p.join(local.path, 'foo')).createSync(skill.path);
      writeConfig(['- path: skills', '  write_allow: [escape]']);

      final String stderr = await run(['--fix'], exitCode: ExitCode.config.code);

      expect(File(p.join(skill.path, 'SKILL.md')).readAsStringSync(), _skillNamed('bar'));
      expect(stderr, contains('Configuration error'));
      expect(
        stderr,
        contains('"write_allow" for "skills" has "escape", which a symlink leads outside'),
      );
    });

    test('--allow-write lets --generate-baseline write a configured ignore_file there', () async {
      final String ignoreFile = p.join(outside.path, 'baseline.json');
      await createDummySkill(
        Directory(p.join(repo.path, 'skills')),
        name: 'foo',
        skillContent: _skillNamed('bar'),
      );
      writeConfig(['- path: skills', '  ignore_file: ${_yamlString(ignoreFile)}']);

      await run(['--generate-baseline', '--allow-write', outside.path], exitCode: 0);

      expect(File(ignoreFile).readAsStringSync(), contains('"foo"'));
    });
  });

  group('fix: in rules', () {
    /// Creates `skills/foo` in [repo] with a `name` that `--fix` changes, and
    /// returns its `SKILL.md`.
    Future<File> mismatchedSkill() async {
      final Directory skill = await createDummySkill(
        Directory(p.join(repo.path, 'skills')),
        name: 'foo',
        skillContent: _skillNamed('bar'),
      );
      return File(p.join(skill.path, 'SKILL.md'));
    }

    /// Writes a configuration whose global rules set `fix` for the name rule
    /// to [global], and whose `skills` target sets it to [target].
    void writeFixConfig({required bool global, bool? target}) {
      File(p.join(repo.path, 'skills_lint.yaml')).writeAsStringSync(
        'skills_lint:\n'
        '  rules:\n'
        '    invalid-skill-name: {severity: error, fix: $global}\n'
        '  directories:\n'
        '    - path: skills\n'
        '${target == null ? '' : '      rules:\n        invalid-skill-name: {fix: $target}\n'}',
      );
    }

    test('fix: false in the global rules keeps --fix from running the fix', () async {
      final File skillMd = await mismatchedSkill();
      writeFixConfig(global: false);

      await run(['--fix'], exitCode: 1);

      expect(skillMd.readAsStringSync(), _skillNamed('bar'));
    });

    test('fix: true on a target overrides fix: false in the global rules', () async {
      final File skillMd = await mismatchedSkill();
      writeFixConfig(global: false, target: true);

      await run(['--fix'], exitCode: 0);

      expect(skillMd.readAsStringSync(), _skillNamed('foo'));
      await run([], exitCode: 0);
    });

    test('--no-<rule>-fix overrides fix: true on a target', () async {
      final File skillMd = await mismatchedSkill();
      writeFixConfig(global: false, target: true);

      await run(['--fix', '--no-invalid-skill-name-fix'], exitCode: 1);

      expect(skillMd.readAsStringSync(), _skillNamed('bar'));
    });

    test('--<rule>-fix overrides fix: false in the global rules', () async {
      final File skillMd = await mismatchedSkill();
      writeFixConfig(global: false);

      await run(['--fix', '--invalid-skill-name-fix'], exitCode: 0);

      expect(skillMd.readAsStringSync(), _skillNamed('foo'));
    });

    test('fix: on a rule without a fix is a configuration error', () async {
      await mismatchedSkill();
      File(
        p.join(repo.path, 'skills_lint.yaml'),
      ).writeAsStringSync('skills_lint:\n  rules:\n    path-does-not-exist: {fix: false}\n');

      final String stderr = await run(['--fix'], exitCode: ExitCode.config.code);

      expect(stderr, contains('rule "path-does-not-exist" has no fix'));
    });

    test('a fix value that is not true or false is a configuration error', () async {
      await mismatchedSkill();
      File(
        p.join(repo.path, 'skills_lint.yaml'),
      ).writeAsStringSync('skills_lint:\n  rules:\n    invalid-skill-name: {fix: maybe}\n');

      final String stderr = await run(['--fix'], exitCode: ExitCode.config.code);

      expect(stderr, contains('"fix" for rule "invalid-skill-name" must be true or false'));
    });
  });

  group('directory names', () {
    // End-to-end defense-in-depth check (`test/skill_writer_test.dart` tests
    // `SkillWriter`'s own `directoryNameRefusal` directly).
    test(
      '--fix does not move a skill out of its directory for a name with a YAML escape',
      () async {
        final skills = Directory(p.join(repo.path, 'skills'))..createSync();
        // Pasted into a double-quoted YAML string, `\x2f` decodes to `/`.
        const crafted = r'"..\x2fescaped"';
        await createDummySkill(skills, name: crafted, skillContent: _skillNamed('foo'));

        await run(['--fix', '-d', 'skills'], exitCode: 1);

        expect(Directory(p.join(repo.path, 'escaped')).existsSync(), isFalse);
        expect(Directory(p.join(skills.path, crafted)).existsSync(), isTrue);
      },
      // Windows does not allow `"` or `\` in a directory name.
      testOn: '!windows',
    );
  });
}

/// [path] as a double-quoted YAML string.
String _yamlString(String path) => '"${path.replaceAll(r'\', r'\\')}"';
