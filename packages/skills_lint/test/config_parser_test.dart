// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_lint/src/config_parser.dart';
import 'package:test/test.dart';

/// Builds a configuration document declaring [directories] and
/// [individualSkills] as authored by a user.
String configYaml({
  List<({String path, String? ignoreFile})> directories = const [],
  List<String> individualSkills = const [],
}) {
  final buffer = StringBuffer('skills_lint:\n');
  if (directories.isNotEmpty) {
    buffer.writeln('  directories:');
    for (final directory in directories) {
      buffer.writeln('    - path: "${directory.path}"');
      if (directory.ignoreFile != null) {
        buffer.writeln('      ignore_file: "${directory.ignoreFile}"');
      }
    }
  }
  if (individualSkills.isNotEmpty) {
    buffer.writeln('  individual_skills:');
    for (final skill in individualSkills) {
      buffer.writeln('    - path: "$skill"');
    }
  }
  return buffer.toString();
}

void main() {
  final String cwd = p.normalize(p.absolute(Directory.current.path));
  final String projectRoot = p.normalize(p.absolute('custom/project/root'));

  group('ConfigParser.parse anchoring', () {
    test('anchors relative paths to the working directory by default', () {
      final Configuration config = ConfigParser.parse(
        configYaml(
          directories: [(path: 'sub/skills', ignoreFile: 'custom_ignore.json')],
          individualSkills: ['single/skill'],
        ),
      );

      expect(config.directoryConfigs.single.path, p.join(cwd, 'sub', 'skills'));
      expect(config.directoryConfigs.single.ignoreFile, p.join(cwd, 'custom_ignore.json'));
      expect(config.individualSkillConfigs.single.path, p.join(cwd, 'single', 'skill'));
    });

    test('anchors relative paths to an explicit baseDirectory', () {
      final Configuration config = ConfigParser.parse(
        configYaml(
          directories: [(path: 'relative/skills', ignoreFile: 'relative/ignore.json')],
          individualSkills: ['relative/single'],
        ),
        baseDirectory: projectRoot,
      );

      expect(config.directoryConfigs.single.path, p.join(projectRoot, 'relative', 'skills'));
      expect(
        config.directoryConfigs.single.ignoreFile,
        p.join(projectRoot, 'relative', 'ignore.json'),
      );
      expect(config.individualSkillConfigs.single.path, p.join(projectRoot, 'relative', 'single'));
    });

    test('anchors relative paths to the directory holding sourcePath', () {
      final String sourcePath = p.join(projectRoot, 'nested', 'skills_lint.yaml');

      final Configuration config = ConfigParser.parse(
        configYaml(directories: [(path: 'skills', ignoreFile: 'ignores.json')]),
        sourcePath: sourcePath,
      );

      expect(config.directoryConfigs.single.path, p.join(projectRoot, 'nested', 'skills'));
      expect(
        config.directoryConfigs.single.ignoreFile,
        p.join(projectRoot, 'nested', 'ignores.json'),
      );
    });

    test('prefers baseDirectory over the directory holding sourcePath', () {
      final Configuration config = ConfigParser.parse(
        configYaml(directories: [(path: 'skills', ignoreFile: null)]),
        sourcePath: p.join(projectRoot, 'nested', 'skills_lint.yaml'),
        baseDirectory: projectRoot,
      );

      expect(config.directoryConfigs.single.path, p.join(projectRoot, 'skills'));
    });

    test('leaves absolute paths untouched', () {
      final String absoluteTarget = p.normalize(p.absolute('some/absolute/dir'));

      final Configuration config = ConfigParser.parse(
        configYaml(directories: [(path: absoluteTarget, ignoreFile: null)]),
        baseDirectory: projectRoot,
      );

      expect(config.directoryConfigs.single.path, absoluteTarget);
    });

    test('expands a tilde path to the home directory', () {
      final String? home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];

      final Configuration config = ConfigParser.parse(
        configYaml(directories: [(path: '~/user_skills', ignoreFile: null)]),
        baseDirectory: projectRoot,
      );

      expect(
        config.directoryConfigs.single.path,
        home == null ? isNotEmpty : p.normalize(p.join(home, 'user_skills')),
      );
    });

    test('reports a non-string path and keeps anchoring the remaining entries', () {
      const yaml = '''
skills_lint:
  directories:
    - path: 123
    - path: "valid/dir"
''';

      final Configuration config = ConfigParser.parse(yaml, baseDirectory: projectRoot);

      expect(config.parsingErrors.single, contains('Directory entry "path" must be a string'));
      expect(config.directoryConfigs.single.path, p.join(projectRoot, 'valid', 'dir'));
    });

    test('quotes the authored path in diagnostics rather than the anchored path', () {
      const yaml = '''
skills_lint:
  directories:
    - path: "relative/dir"
      unknown_key: true
''';

      final Configuration config = ConfigParser.parse(yaml, baseDirectory: projectRoot);

      expect(
        config.parsingErrors.single,
        'Unrecognized key "unknown_key" in directory entry for "relative/dir".',
      );
    });

    test('returns an empty configuration for content without a skills_lint key', () {
      expect(ConfigParser.parse('').directoryConfigs, isEmpty);
      expect(ConfigParser.parse('other_key: 123').directoryConfigs, isEmpty);
    });
  });

  group('ConfigParser.loadConfig', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('config_parser_test.');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('anchors targets to the directory holding the configuration file', () async {
      final subDir = Directory(p.join(tempDir.path, 'nested', 'subproject'))
        ..createSync(recursive: true);
      final configFile = File(p.join(subDir.path, 'skills_lint.yaml'));
      await configFile.writeAsString(
        configYaml(
          directories: [(path: 'skills', ignoreFile: 'ignores.json')],
          individualSkills: ['individual_skill'],
        ),
      );
      final String expectedBase = p.normalize(p.absolute(subDir.path));

      final Configuration config = await ConfigParser.loadConfig(path: configFile.path);

      expect(config.directoryConfigs.single.path, p.join(expectedBase, 'skills'));
      expect(config.directoryConfigs.single.ignoreFile, p.join(expectedBase, 'ignores.json'));
      expect(config.individualSkillConfigs.single.path, p.join(expectedBase, 'individual_skill'));
    });

    test('throws when an explicit configuration file is missing', () {
      expect(
        () => ConfigParser.loadConfig(path: p.join(tempDir.path, 'missing_config.yaml')),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('returns an empty configuration when the default file is missing', () async {
      final Configuration config = await IOOverrides.runZoned(
        () => ConfigParser.loadConfig(),
        getCurrentDirectory: () => tempDir,
      );

      expect(config.directoryConfigs, isEmpty);
      expect(config.individualSkillConfigs, isEmpty);
      expect(config.parsingErrors, isEmpty);
    });

    test('captures YAML syntax errors as parsing errors', () async {
      final configFile = File(p.join(tempDir.path, 'invalid_syntax.yaml'));
      await configFile.writeAsString('''
skills_lint:
  directories: [unclosed list
''');

      final Configuration config = await ConfigParser.loadConfig(path: configFile.path);

      expect(config.parsingErrors.single, contains('Failed to parse'));
    });
  });
}
