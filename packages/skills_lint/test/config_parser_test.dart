// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_lint/src/config_parser.dart';
import 'package:test/test.dart';

void main() {
  group('ConfigParser.parseString', () {
    test('canonicalizes target paths relative to default baseDirectory (CWD)', () {
      const yaml = '''
skills_lint:
  directories:
    - path: "sub/skills"
      ignore_file: "custom_ignore.json"
  individual_skills:
    - path: "single/skill"
''';
      final Configuration config = ConfigParser.parseString(yaml);
      final String cwd = p.normalize(p.absolute(Directory.current.path));

      expect(config.directoryConfigs, hasLength(1));
      expect(config.directoryConfigs.first.path, equals(p.join(cwd, 'sub', 'skills')));
      expect(config.directoryConfigs.first.ignoreFile, equals(p.join(cwd, 'custom_ignore.json')));

      expect(config.individualSkillConfigs, hasLength(1));
      expect(config.individualSkillConfigs.first.path, equals(p.join(cwd, 'single', 'skill')));
    });

    test('canonicalizes target paths relative to explicit baseDirectory', () {
      const yaml = '''
skills_lint:
  directories:
    - path: "relative/skills"
      ignore_file: "relative/ignore.json"
  individual_skills:
    - path: "relative/single"
''';
      final String customBase = p.normalize(p.absolute('custom/project/root'));
      final Configuration config = ConfigParser.parseString(yaml, baseDirectory: customBase);

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

    test('preserves absolute target paths and expands tilde paths', () {
      final String absoluteTarget = p.normalize(p.absolute('some/absolute/dir'));
      final yaml =
          '''
skills_lint:
  directories:
    - path: '$absoluteTarget'
    - path: "~/user_skills"
''';
      final String customBase = p.normalize(p.absolute('custom/project/root'));
      final Configuration config = ConfigParser.parseString(yaml, baseDirectory: customBase);

      expect(config.directoryConfigs, hasLength(2));
      expect(config.directoryConfigs[0].path, equals(absoluteTarget));

      final String? home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
      if (home != null) {
        expect(config.directoryConfigs[1].path, equals(p.normalize(p.join(home, 'user_skills'))));
      }
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

    test('anchors targets and ignore files to the directory of the loaded config file', () async {
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

      final Configuration config = await ConfigParser.loadConfig(path: configFile.path);

      final String expectedBase = p.normalize(p.absolute(subDir.path));
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
  });
}
