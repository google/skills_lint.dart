// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_lint/src/config_parser.dart';
import 'package:skills_lint/src/config_source.dart';
import 'package:skills_lint/src/models/target_declaration.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// Builds a configuration document declaring [directories] and
/// [individualSkills] as authored by a user.
///
/// Serializing through [Configuration] keeps the fixture valid for paths that
/// need escaping, such as a Windows path holding backslashes.
String configYaml({
  List<({String path, String? ignoreFile})> directories = const [],
  List<String> individualSkills = const [],
}) {
  return Configuration(
    directoryConfigs: <LintTargetConfig>[
      for (final directory in directories)
        LintTargetConfig(path: directory.path, ignoreFile: directory.ignoreFile),
    ],
    individualSkillConfigs: <LintTargetConfig>[
      for (final skill in individualSkills) LintTargetConfig(path: skill),
    ],
  ).toYamlString();
}

void main() {
  final String cwd = p.normalize(p.absolute(Directory.current.path));
  final String projectRoot = p.normalize(p.absolute('custom/project/root'));

  group('ConfigParser.parse anchoring', () {
    test('accepts a file source for paths and diagnostics', () {
      final String file = p.join(projectRoot, 'nested', 'skills_lint.yaml');
      final Configuration config = ConfigParser.parse(
        configYaml(directories: [(path: 'skills', ignoreFile: null)]),
        configSource: ConfigSource.file(file),
      );

      expect(config.directoryConfigs.single.path, p.join(projectRoot, 'nested', 'skills'));
      expect(declarationOf(config.directoryConfigs.single)?.source?.file, file);

      final Configuration invalid = ConfigParser.parse(
        ': invalid: [',
        configSource: ConfigSource.file(file),
      );
      expect(invalid.parsingErrors.single, contains(file));
    });

    test('accepts a directory source for in-memory content', () {
      final Configuration config = ConfigParser.parse(
        configYaml(directories: [(path: 'skills', ignoreFile: null)]),
        configSource: ConfigSource.directory(projectRoot),
      );

      expect(config.directoryConfigs.single.path, p.join(projectRoot, 'skills'));
      expect(declarationOf(config.directoryConfigs.single)?.source, isNull);
    });

    test('uses the same source for decoded YAML', () {
      final Configuration config = ConfigParser.fromYaml(
        loadYaml(configYaml(individualSkills: ['skill'])),
        configSource: ConfigSource.directory(projectRoot),
      );

      expect(config.individualSkillConfigs.single.path, p.join(projectRoot, 'skill'));
    });

    test('rejects mixing configSource with deprecated source arguments', () {
      expect(
        () => ConfigParser.parse(
          '',
          configSource: ConfigSource.directory(projectRoot),
          sourcePath: 'skills_lint.yaml',
        ),
        throwsArgumentError,
      );
    });

    test('rejects mixing configSource with baseDirectory', () {
      expect(
        () => ConfigParser.parse(
          '',
          configSource: ConfigSource.directory(projectRoot),
          baseDirectory: projectRoot,
        ),
        throwsArgumentError,
      );
    });

    test('rejects mixed sources for empty decoded YAML', () {
      expect(
        () => ConfigParser.fromYaml(
          null,
          configSource: ConfigSource.directory(projectRoot),
          sourcePath: 'skills_lint.yaml',
        ),
        throwsArgumentError,
      );
    });

    test('rejects mixed sources before parsing invalid YAML', () {
      expect(
        () => ConfigParser.parse(
          'a: [',
          configSource: ConfigSource.directory(projectRoot),
          sourcePath: 'skills_lint.yaml',
        ),
        throwsArgumentError,
      );
    });

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
      final String file = p.join(projectRoot, 'nested', 'skills_lint.yaml');
      final Configuration config = ConfigParser.parse(
        configYaml(directories: [(path: 'skills', ignoreFile: 'ignore.json')]),
        sourcePath: file,
        baseDirectory: projectRoot,
      );

      expect(config.directoryConfigs.single.path, p.join(projectRoot, 'skills'));
      expect(config.directoryConfigs.single.ignoreFile, p.join(projectRoot, 'ignore.json'));
      expect(declarationOf(config.directoryConfigs.single)?.source?.file, file);

      final Configuration invalid = ConfigParser.parse(
        'a: [',
        sourcePath: file,
        baseDirectory: projectRoot,
      );
      expect(invalid.parsingErrors.single, contains(file));
    });

    test('accepts both deprecated arguments for decoded YAML', () {
      final String file = p.join(projectRoot, 'nested', 'skills_lint.yaml');
      final Configuration config = ConfigParser.fromYaml(
        loadYaml(configYaml(directories: [(path: 'skills', ignoreFile: 'ignore.json')])),
        sourcePath: file,
        baseDirectory: projectRoot,
      );

      expect(config.directoryConfigs.single.path, p.join(projectRoot, 'skills'));
      expect(config.directoryConfigs.single.ignoreFile, p.join(projectRoot, 'ignore.json'));
      expect(declarationOf(config.directoryConfigs.single)?.source?.file, file);
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

  group('declarationOf', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('config_parser_declaration_test.');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('records the declared text, file, line and anchor of each target', () async {
      final configFile = File(p.join(tempDir.path, 'tool', 'skills_lint.yaml'))
        ..createSync(recursive: true)
        ..writeAsStringSync('''
# A comment above everything.
skills_lint:

  # Where the skills live.
  directories:
    - path: ".agents/skills"
  individual_skills:
    - path: "one/skill"
''');

      final Configuration config = await ConfigParser.loadConfig(path: configFile.path);
      final String expectedFile = p.normalize(p.absolute(configFile.path));
      final String expectedAnchor = p.dirname(expectedFile);

      final TargetDeclaration? directory = declarationOf(config.directoryConfigs.single);
      expect(directory?.declaredPath, '.agents/skills');
      expect(directory?.source?.file, expectedFile);
      // Line 6: `directories:` on line 5 is followed by its entry.
      expect(directory?.source?.line, 6);
      expect(directory?.anchorDirectory, expectedAnchor);

      final TargetDeclaration? skill = declarationOf(config.individualSkillConfigs.single);
      expect(skill?.declaredPath, 'one/skill');
      // Line 8: `individual_skills:` on line 7 is followed by its entry.
      expect(skill?.source?.line, 8);
    });

    test('records the line of an entry in a flow-style list', () {
      final Configuration config = ConfigParser.parse(
        'skills_lint:\n'
        '  directories: [{path: a}, {path: b}]\n',
        sourcePath: p.join(tempDir.path, 'skills_lint.yaml'),
      );

      expect(config.directoryConfigs.map((t) => declarationOf(t)?.source?.line), [2, 2]);
    });

    test('names no file for content parsed without a source path', () {
      final Configuration config = ConfigParser.parse(configYaml(individualSkills: ['a']));

      final TargetDeclaration? declaration = declarationOf(config.individualSkillConfigs.single);
      expect(declaration?.declaredPath, 'a');
      expect(declaration?.source, isNull);
    });

    test('a target built directly has no declaration', () {
      expect(declarationOf(const LintTargetConfig(path: 'skills')), isNull);
    });
  });
}
