// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_lint/src/config_parser.dart';
import 'package:test/test.dart';

void main() {
  group('ConfigParser.parseString', () {
    test('anchors relative target and ignore paths to default baseDirectory (CWD)', () {
      // Arrange
      const yaml = '''
skills_lint:
  directories:
    - path: "sub/skills"
      ignore_file: "custom_ignore.json"
  individual_skills:
    - path: "single/skill"
''';
      final String expectedCwd = p.normalize(p.absolute(Directory.current.path));

      // Act
      final Configuration config = ConfigParser.parseString(yaml);

      // Assert
      expect(config.directoryConfigs, hasLength(1));
      expect(config.directoryConfigs.first.path, equals(p.join(expectedCwd, 'sub', 'skills')));
      expect(
        config.directoryConfigs.first.ignoreFile,
        equals(p.join(expectedCwd, 'custom_ignore.json')),
      );

      expect(config.individualSkillConfigs, hasLength(1));
      expect(
        config.individualSkillConfigs.first.path,
        equals(p.join(expectedCwd, 'single', 'skill')),
      );
    });

    test('anchors relative target and ignore paths to explicit baseDirectory', () {
      // Arrange
      const yaml = '''
skills_lint:
  directories:
    - path: "relative/skills"
      ignore_file: "relative/ignore.json"
  individual_skills:
    - path: "relative/single"
''';
      final String customBase = p.normalize(p.absolute('custom/project/root'));

      // Act
      final Configuration config = ConfigParser.parseString(yaml, baseDirectory: customBase);

      // Assert
      expect(config.directoryConfigs, hasLength(1));
      expect(config.directoryConfigs.first.path, equals(p.join(customBase, 'relative', 'skills')));
      expect(
        config.directoryConfigs.first.ignoreFile,
        equals(p.join(customBase, 'relative', 'ignore.json')),
      );

      expect(config.individualSkillConfigs, hasLength(1));
      expect(
        config.individualSkillConfigs.first.path,
        equals(p.join(customBase, 'relative', 'single')),
      );
    });

    test('preserves absolute target paths without prepending baseDirectory', () {
      // Arrange
      final String absoluteTarget = p.normalize(p.absolute('some/absolute/dir'));
      final yaml =
          '''
skills_lint:
  directories:
    - path: '$absoluteTarget'
''';
      final String customBase = p.normalize(p.absolute('custom/project/root'));

      // Act
      final Configuration config = ConfigParser.parseString(yaml, baseDirectory: customBase);

      // Assert
      expect(config.directoryConfigs, hasLength(1));
      expect(config.directoryConfigs.first.path, equals(absoluteTarget));
    });

    test('expands tilde (~) target paths to user home directory', () {
      // Arrange
      const yaml = '''
skills_lint:
  directories:
    - path: "~/user_skills"
''';
      final String customBase = p.normalize(p.absolute('custom/project/root'));
      final String? home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];

      // Act
      final Configuration config = ConfigParser.parseString(yaml, baseDirectory: customBase);

      // Assert
      expect(config.directoryConfigs, hasLength(1));
      if (home != null) {
        expect(
          config.directoryConfigs.first.path,
          equals(p.normalize(p.join(home, 'user_skills'))),
        );
      }
    });

    test('records parsingErrors for non-string path types while continuing parsing', () {
      // Arrange
      const yaml = '''
skills_lint:
  directories:
    - path: 123
    - path: "valid/dir"
''';
      final String customBase = p.normalize(p.absolute('custom/project/root'));

      // Act
      final Configuration config = ConfigParser.parseString(yaml, baseDirectory: customBase);

      // Assert
      expect(config.parsingErrors, hasLength(1));
      expect(config.parsingErrors.first, contains('Directory entry "path" must be a string'));
      expect(config.directoryConfigs, hasLength(1));
      expect(config.directoryConfigs.first.path, equals(p.join(customBase, 'valid', 'dir')));
    });

    test('returns empty Configuration when content is empty or contains no skills_lint key', () {
      // Arrange & Act & Assert
      expect(ConfigParser.parseString('').directoryConfigs, isEmpty);
      expect(ConfigParser.parseString('other_key: 123').directoryConfigs, isEmpty);
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

    test('anchors relative targets and ignore files to directory containing config file', () async {
      // Arrange
      final subDir = Directory(p.join(tempDir.path, 'nested', 'subproject'))
        ..createSync(recursive: true);
      final configFile = File(p.join(subDir.path, 'skills_lint.yaml'));
      await configFile.writeAsString('''
skills_lint:
  directories:
    - path: "skills"
      ignore_file: "ignores.json"
  individual_skills:
    - path: "individual_skill"
''');
      final String expectedBase = p.normalize(p.absolute(subDir.path));

      // Act
      final Configuration config = await ConfigParser.loadConfig(path: configFile.path);

      // Assert
      expect(config.directoryConfigs, hasLength(1));
      expect(config.directoryConfigs.first.path, equals(p.join(expectedBase, 'skills')));
      expect(
        config.directoryConfigs.first.ignoreFile,
        equals(p.join(expectedBase, 'ignores.json')),
      );

      expect(config.individualSkillConfigs, hasLength(1));
      expect(
        config.individualSkillConfigs.first.path,
        equals(p.join(expectedBase, 'individual_skill')),
      );
    });

    test('throws FileSystemException when explicit custom config file does not exist', () async {
      // Arrange
      final String missingPath = p.join(tempDir.path, 'missing_config.yaml');

      // Act & Assert
      expect(() => ConfigParser.loadConfig(path: missingPath), throwsA(isA<FileSystemException>()));
    });

    test('returns empty Configuration when default config file does not exist', () async {
      // Arrange
      final emptyDir = Directory(p.join(tempDir.path, 'empty_dir'))..createSync();

      // Act
      final Configuration config = await ConfigParser.loadConfig(baseDirectory: emptyDir.path);

      // Assert
      expect(config.directoryConfigs, isEmpty);
      expect(config.individualSkillConfigs, isEmpty);
      expect(config.parsingErrors, isEmpty);
    });

    test('captures YAML syntax errors into parsingErrors list', () async {
      // Arrange
      final configFile = File(p.join(tempDir.path, 'invalid_syntax.yaml'));
      await configFile.writeAsString('''
skills_lint:
  directories: [unclosed list
''');

      // Act
      final Configuration config = await ConfigParser.loadConfig(path: configFile.path);

      // Assert
      expect(config.parsingErrors, hasLength(1));
      expect(config.parsingErrors.first, contains('Failed to parse'));
    });
  });
}
