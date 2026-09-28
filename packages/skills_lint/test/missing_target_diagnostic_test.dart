// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_lint/src/missing_target_diagnostic.dart';
import 'package:skills_lint/src/models/target_declaration.dart';
import 'package:test/test.dart';

void main() {
  group('missingTargetDiagnostic', () {
    late Directory tempDir;
    late String repo;
    late String tool;
    late String configFile;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('missing_target_diagnostic_test.');
      repo = tempDir.path;
      tool = p.join(repo, 'tool');
      configFile = p.join(tool, 'skills_lint.yaml');
      Directory(p.join(repo, '.agents', 'skills')).createSync(recursive: true);
      Directory(tool).createSync();
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    group('for a target declared in a configuration file', () {
      late MissingTargetDiagnostic diagnostic;

      setUp(() {
        diagnostic = missingTargetDiagnostic(
          kind: MissingTargetKind.skillsRoot,
          resolvedPath: p.join(tool, '.agents', 'skills'),
          workingDirectory: repo,
          declaration: TargetDeclaration(
            declaredPath: '.agents/skills',
            anchorDirectory: tool,
            source: (file: configFile, line: 3),
          ),
        );
      });

      test('keeps the resolved path on the first line', () {
        expect(
          diagnostic.text.split('\n').first,
          allOf(contains('root directory does not exist'), contains(p.join(tool, '.agents'))),
        );
      });

      test('names the declared text, the file and line, and the anchor', () {
        expect(
          diagnostic.text,
          allOf(contains('".agents/skills"'), contains('$configFile:3'), contains(tool)),
        );
      });

      test('suggests the path the author meant', () {
        expect(diagnostic.text, contains('Did you mean "../.agents/skills"?'));
        expect(diagnostic.markdown, contains('../.agents/skills'));
      });

      test('points the location at the declaring line of the configuration file', () {
        expect(diagnostic.file, configFile);
        expect(diagnostic.region?.startLine, 3);
      });

      test('explains in markdown that the path is not relative to the working directory', () {
        expect(
          diagnostic.markdown,
          allOf(contains('working directory'), contains(tool), contains('.agents/skills')),
        );
      });
    });

    test('an in-memory configuration names no file or line', () {
      final String missing = p.join(repo, 'missing');
      final MissingTargetDiagnostic diagnostic = missingTargetDiagnostic(
        kind: MissingTargetKind.skillsRoot,
        resolvedPath: missing,
        workingDirectory: repo,
        declaration: TargetDeclaration(declaredPath: 'missing', anchorDirectory: repo),
      );

      expect(diagnostic.text, allOf(contains('in configuration'), isNot(contains('.yaml'))));
      expect(diagnostic.file, missing);
      expect(diagnostic.region, isNull);
      expect(diagnostic.markdown, contains(repo));
    });

    test('names a root anchor without doubling its separator', () {
      final String root = p.rootPrefix(repo);
      final MissingTargetDiagnostic diagnostic = missingTargetDiagnostic(
        kind: MissingTargetKind.skillsRoot,
        resolvedPath: p.join(root, 'no-such-dir-for-skills-lint'),
        workingDirectory: repo,
        declaration: TargetDeclaration(
          declaredPath: 'no-such-dir-for-skills-lint',
          anchorDirectory: root,
          source: (file: p.join(root, 'skills_lint.yaml'), line: 3),
        ),
      );

      expect(diagnostic.markdown, isNot(contains('${p.separator}${p.separator}')));
    });

    group('for a target typed on the command line', () {
      test('suggests a near-miss directory without describing a declaration', () {
        final MissingTargetDiagnostic diagnostic = missingTargetDiagnostic(
          kind: MissingTargetKind.skillsRoot,
          resolvedPath: p.join(repo, '.agents', 'skils'),
          workingDirectory: repo,
          cliText: '.agents/skils',
        );

        expect(diagnostic.text, contains('Did you mean ".agents/skills"?'));
        expect(diagnostic.text, isNot(contains('Declared as')));
        expect(diagnostic.markdown, isNot(contains('configuration')));
        expect(diagnostic.file, p.join(repo, '.agents', 'skils'));
        expect(diagnostic.region, isNull);
      });

      test('stays a single line when nothing is close', () {
        final MissingTargetDiagnostic diagnostic = missingTargetDiagnostic(
          kind: MissingTargetKind.skill,
          resolvedPath: p.join(repo, 'unrelated'),
          workingDirectory: repo,
          cliText: 'unrelated',
        );

        expect(diagnostic.text, contains('skill directory does not exist'));
        expect(diagnostic.text.split('\n'), hasLength(1));
        expect(diagnostic.markdown, isNull);
      });
    });
  });
}
