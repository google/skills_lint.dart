// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_lint/skills_lint.dart';
import 'package:test/test.dart';

/// Guards the boundary canonicalization contract documented on
/// `canonicalizePath`.
///
/// Paths are anchored where they enter the tool. A contributor who adds a rule,
/// a flag, or a configuration key inherits absolute paths and does not have to
/// remember to canonicalize. These tests fail if that stops being true.

/// Files permitted to anchor paths, with the boundary each one owns and the
/// number of times the canonicalization helpers may appear in it.
///
/// The count is a tripwire rather than a budget. Anchoring a path somewhere new
/// is a design decision, so it should reach review as a deliberate edit to this
/// table. The count for `path_utils.dart` covers the helper declarations
/// themselves, since the pattern below matches a declaration as readily as a
/// call.
const Map<String, ({int matches, String owns})> boundaryFiles =
    <String, ({int matches, String owns})>{
      'lib/src/path_utils.dart': (matches: 5, owns: 'declares the canonicalization helpers'),
      'lib/src/config_parser.dart': (
        matches: 5,
        owns: 'anchors paths read from a configuration file',
      ),
      'lib/src/entry_point.dart': (
        matches: 4,
        owns: 'anchors paths supplied by the CLI or an API caller',
      ),
      'lib/src/validation_session.dart': (
        matches: 1,
        owns:
            'funnels path ingestion through _ingestPath, so its other members '
            'compare paths without consulting the working directory',
      ),
    };

/// Matches a use of the canonicalization helpers.
///
/// The pattern tolerates whitespace before the parenthesis so that a call
/// written as `canonicalizePath (x)` cannot slip past the scan.
final RegExp canonicalizationCall = RegExp(r'\bcanonicalizePath(s|OrNull)?\s*\(');

/// Every `.dart` file under `lib/`, keyed by its package-relative path.
Map<String, String> libSources() {
  return <String, String>{
    for (final FileSystemEntity entity in Directory('lib').listSync(recursive: true))
      if (entity is File && entity.path.endsWith('.dart'))
        p.relative(entity.path).replaceAll(r'\', '/'): entity.readAsStringSync(),
  };
}

/// Writes a configuration file declaring [target] inside [directory].
File writeConfig(Directory directory, {required String target, String? ignoreFile}) {
  final configuration = Configuration(
    directoryConfigs: <LintTargetConfig>[
      LintTargetConfig(
        path: target,
        ignoreFile: ignoreFile,
        ruleConfigs: const <String, RuleConfigPatch>{
          'check-trailing-whitespace': RuleConfigPatch(severity: AnalysisSeverity.error),
        },
      ),
    ],
  );
  return File(p.join(directory.path, 'skills_lint.yaml'))
    ..writeAsStringSync(configuration.toYamlString());
}

void main() {
  group('canonicalization stays at the boundaries', () {
    test('no file outside a boundary anchors paths', () {
      final offenders = <String, String>{
        for (final source in libSources().entries)
          if (!boundaryFiles.containsKey(source.key) && canonicalizationCall.hasMatch(source.value))
            source.key: source.value,
      };

      expect(
        offenders.keys,
        isEmpty,
        reason:
            'Paths are anchored once, at the boundary where they enter the tool:\n'
            '${boundaryFiles.entries.map((MapEntry<String, ({int matches, String owns})> e) => '  ${e.key}: ${e.value.owns}').join('\n')}\n'
            'Code behind a boundary receives absolute paths. If a path reaches '
            '${offenders.keys.join(', ')} unanchored, anchor it at the boundary '
            'it entered through instead of here.',
      );
    });

    test('each boundary anchors paths only where it declares', () {
      final Map<String, String> sources = libSources();

      for (final MapEntry<String, ({int matches, String owns})> boundary in boundaryFiles.entries) {
        expect(
          canonicalizationCall.allMatches(sources[boundary.key]!),
          hasLength(boundary.value.matches),
          reason:
              '${boundary.key} ${boundary.value.owns}.\n'
              'Anchoring a path somewhere new is a design decision. If the added '
              'call belongs at this boundary, raise the count in boundaryFiles so '
              'the decision is visible in review. Otherwise anchor the path at the '
              'boundary it entered through.',
        );
      }
    });
  });

  group('parsed configurations expose absolute paths', () {
    const authoredPaths = <String>[
      'skills',
      './skills',
      'nested/skills',
      '../sibling/skills',
      '/tmp/absolute/skills',
      '~/home/skills',
    ];

    for (final authored in authoredPaths) {
      test('anchors "$authored"', () {
        final Configuration parsed = ConfigParser.parse(
          Configuration(
            directoryConfigs: <LintTargetConfig>[
              LintTargetConfig(path: authored, ignoreFile: authored),
            ],
          ).toYamlString(),
          sourcePath: p.join(p.current, 'project', 'skills_lint.yaml'),
        );

        expect(p.isAbsolute(parsed.directoryConfigs.single.path), isTrue);
        expect(p.isAbsolute(parsed.directoryConfigs.single.ignoreFile!), isTrue);
      });
    }
  });

  group('hand-built configurations anchor to the working directory', () {
    late Directory tempDir;
    late Directory projectDir;
    late Directory elsewhereDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('path_boundary_authored_test.');
      projectDir = Directory(p.join(tempDir.path, 'project'))..createSync();
      elsewhereDir = Directory(p.join(tempDir.path, 'elsewhere'))..createSync();
      Directory(p.join(projectDir.path, 'skills')).createSync();
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    /// A configuration that targets `skills` with a path the caller authored.
    ///
    /// [LintTargetConfig] doubles as the authoring surface, so an instance that
    /// never passed through [ConfigParser] can hold a relative path.
    const authoredConfiguration = Configuration(
      directoryConfigs: <LintTargetConfig>[
        LintTargetConfig(
          path: 'skills',
          ruleConfigs: <String, RuleConfigPatch>{
            'check-trailing-whitespace': RuleConfigPatch(severity: AnalysisSeverity.error),
          },
        ),
      ],
    );

    /// Resolves the rules for a skill under `projectDir` with
    /// [workingDirectory] current.
    Map<String, RuleConfig> resolveWithWorkingDirectory(Directory workingDirectory) {
      return IOOverrides.runZoned(() {
        final session = ValidationSession(
          config: authoredConfiguration,
          ignoreFileOverride: null,
          customRules: const <SkillRule>[],
          printWarnings: false,
          fastFail: false,
          quiet: true,
          generateBaseline: false,
          fix: false,
          fixApply: false,
        );
        return session.resolveRuleConfigsForPath(p.join(projectDir.path, 'skills', 'a-skill'));
      }, getCurrentDirectory: () => workingDirectory);
    }

    test('an authored relative target covers a skill under the working directory', () {
      expect(
        resolveWithWorkingDirectory(projectDir)['check-trailing-whitespace']?.severity,
        AnalysisSeverity.error,
      );
    });

    test('an authored relative target stops covering from another directory', () {
      expect(
        resolveWithWorkingDirectory(elsewhereDir)['check-trailing-whitespace']?.severity,
        isNot(AnalysisSeverity.error),
        reason:
            'A relative path on a configuration that no parser anchored means '
            'relative to the working directory, so a skill outside that '
            'directory falls outside the target.',
      );
    });
  });

  group('results do not depend on the working directory', () {
    late Directory tempDir;
    late Directory projectDir;
    late Directory elsewhereDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('path_boundary_test.');
      projectDir = Directory(p.join(tempDir.path, 'project'))..createSync();
      elsewhereDir = Directory(p.join(tempDir.path, 'elsewhere'))..createSync();
      Directory(p.join(projectDir.path, 'skills')).createSync();
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    /// Loads the project configuration while [workingDirectory] is current.
    Future<Configuration> loadFrom(Directory workingDirectory) {
      return IOOverrides.runZoned(
        () => ConfigParser.loadConfig(path: p.join(projectDir.path, 'skills_lint.yaml')),
        getCurrentDirectory: () => workingDirectory,
      );
    }

    test('a configuration resolves to the same targets from any directory', () async {
      writeConfig(projectDir, target: 'skills', ignoreFile: 'skills/ignores.json');

      final Configuration fromProject = await loadFrom(projectDir);
      final Configuration fromElsewhere = await loadFrom(elsewhereDir);

      expect(fromProject.directoryConfigs.single.path, p.join(projectDir.path, 'skills'));
      expect(fromElsewhere.toYamlString(), fromProject.toYamlString());
    });

    test('the session matches a configured target against a skill under it', () async {
      writeConfig(projectDir, target: 'skills');
      final Configuration configuration = await loadFrom(elsewhereDir);

      final session = ValidationSession(
        config: configuration,
        ignoreFileOverride: null,
        customRules: const <SkillRule>[],
        printWarnings: false,
        fastFail: false,
        quiet: true,
        generateBaseline: false,
        fix: false,
        fixApply: false,
      );

      final Map<String, RuleConfig> resolved = session.resolveRuleConfigsForPath(
        p.join(projectDir.path, 'skills', 'a-skill'),
      );

      expect(resolved['check-trailing-whitespace']?.severity, AnalysisSeverity.error);
    });
  });
}
