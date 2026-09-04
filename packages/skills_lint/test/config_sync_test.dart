// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  group('Configuration Synchronization', () {
    test('root and package-level skills_lint.yaml define equivalent configurations', () {
      final rootConfigFile = File('../../skills_lint.yaml');
      final packageConfigFile = File('skills_lint.yaml');

      expect(rootConfigFile.existsSync(), isTrue, reason: 'Root skills_lint.yaml must exist');
      expect(packageConfigFile.existsSync(), isTrue, reason: 'Package skills_lint.yaml must exist');

      final Object? rootDoc = loadYaml(rootConfigFile.readAsStringSync());
      final Object? pkgDoc = loadYaml(packageConfigFile.readAsStringSync());

      expect(rootDoc, isA<YamlMap>());
      expect(pkgDoc, isA<YamlMap>());

      final rootRoot = rootDoc! as YamlMap;
      final pkgRoot = pkgDoc! as YamlMap;

      final rootYaml = rootRoot['skills_lint'] as YamlMap;
      final pkgYaml = pkgRoot['skills_lint'] as YamlMap;

      // 1. Verify global rules match
      final Object? rootRules = rootYaml['rules'];
      final Object? pkgRules = pkgYaml['rules'];
      expect(rootRules, equals(pkgRules), reason: 'Global rules section must match');

      // 2. Verify directory configs match modulo path prefixes
      final rootDirs = rootYaml['directories'] as YamlList?;
      final pkgDirs = pkgYaml['directories'] as YamlList?;

      expect(rootDirs, isNotNull);
      expect(pkgDirs, isNotNull);
      expect(rootDirs!.length, equals(pkgDirs!.length));

      for (var i = 0; i < rootDirs.length; i++) {
        final rootEntry = rootDirs[i] as YamlMap;
        final pkgEntry = pkgDirs[i] as YamlMap;

        final rootPath = rootEntry['path'].toString();
        final pkgPath = pkgEntry['path'].toString();

        // Normalize paths to repository root perspective
        final String rootCanonical = p.normalize(rootPath);
        final String pkgCanonical = p.normalize(p.join('packages/skills_lint', pkgPath));
        expect(
          rootCanonical,
          equals(pkgCanonical),
          reason: 'Directory path $i must resolve to same repository path',
        );

        expect(
          rootEntry['rules'],
          equals(pkgEntry['rules']),
          reason: 'Rules for directory $rootCanonical must match',
        );

        if (rootEntry['ignore_file'] != null || pkgEntry['ignore_file'] != null) {
          final String rootIgnore = p.normalize(rootEntry['ignore_file'].toString());
          final String pkgIgnore = p.normalize(
            p.join('packages/skills_lint', pkgEntry['ignore_file'].toString()),
          );
          expect(
            rootIgnore,
            equals(pkgIgnore),
            reason: 'Ignore file for directory $rootCanonical must match',
          );
        }
      }

      // 3. Verify individual skills match modulo path prefixes
      final rootSkills = rootYaml['individual_skills'] as YamlList?;
      final pkgSkills = pkgYaml['individual_skills'] as YamlList?;

      if (rootSkills != null || pkgSkills != null) {
        expect(rootSkills, isNotNull);
        expect(pkgSkills, isNotNull);
        expect(rootSkills!.length, equals(pkgSkills!.length));

        for (var i = 0; i < rootSkills.length; i++) {
          final rootEntry = rootSkills[i] as YamlMap;
          final pkgEntry = pkgSkills[i] as YamlMap;

          final rootPath = rootEntry['path'].toString();
          final pkgPath = pkgEntry['path'].toString();

          final String rootCanonical = p.normalize(rootPath);
          final String pkgCanonical = p.normalize(p.join('packages/skills_lint', pkgPath));
          expect(
            rootCanonical,
            equals(pkgCanonical),
            reason: 'Skill path $i must resolve to same repository path',
          );

          expect(
            rootEntry['rules'],
            equals(pkgEntry['rules']),
            reason: 'Rules for individual skill $rootCanonical must match',
          );
        }
      }
    });
  });
}
