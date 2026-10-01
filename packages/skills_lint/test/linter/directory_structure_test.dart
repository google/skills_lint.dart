// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_lint/src/models/analysis_severity.dart';
import 'package:skills_lint/src/models/rule_config.dart';
import 'package:skills_lint/src/models/validation_error.dart';
import 'package:skills_lint/src/validator.dart';
import 'package:test/test.dart';

class MockInaccessibleFile implements File {
  MockInaccessibleFile(this._path);
  final String _path;

  @override
  String get path => _path;

  @override
  bool existsSync() => true;

  @override
  Future<String> readAsString({Encoding encoding = utf8}) =>
      Future<String>.error(FileSystemException('File is inaccessible', _path));

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

base class TestIOOverrides extends IOOverrides {
  TestIOOverrides(this.targetPath);
  final String targetPath;

  @override
  File createFile(String path) {
    if (path == targetPath) {
      return MockInaccessibleFile(path);
    }
    return super.createFile(path);
  }
}

void main() {
  group('Directory Structure Validation', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('skill_test.');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('fails if directory does not exist', () async {
      final nonExistentDir = Directory('path/to/nothing');
      final validator = Validator();
      final ValidationResult result = await validator.validate(nonExistentDir);

      expect(result.isValid, isFalse);
      expect(result.errors, contains(contains('Directory does not exist')));
    });

    test('fails if path is a file', () async {
      final file = File('${tempDir.path}/some_file');
      await file.create();
      final validator = Validator();
      final ValidationResult result = await validator.validate(Directory(file.path));

      expect(result.isValid, isFalse);
      expect(result.errors, contains(contains('is not a directory')));
    });

    test('fails if SKILL.md is missing', () async {
      final validator = Validator();
      final ValidationResult result = await validator.validate(tempDir);

      expect(result.isValid, isFalse);
      expect(result.errors, contains(contains('SKILL.md is missing')));
    });

    test('fails if SKILL.md cannot be read', () async {
      final skillDir = Directory(p.join(tempDir.path, 'test-skill-inaccessible'));
      await skillDir.create();
      final String filePath = p.join(skillDir.path, 'SKILL.md');

      final overrides = TestIOOverrides(filePath);
      await IOOverrides.runWithIOOverrides(() async {
        final validator = Validator();
        final ValidationResult validationResult = await validator.validate(skillDir);

        expect(validationResult.isValid, isFalse);
        expect(
          _describe(validationResult.validationErrors),
          contains(_hasRule(Validator.skillFileInaccessible)),
        );
      }, overrides);
    });

    test('obeys skill-file-inaccessible severity override', () async {
      final skillDir = Directory(p.join(tempDir.path, 'test-skill-override'));
      await skillDir.create();
      final String filePath = p.join(skillDir.path, 'SKILL.md');

      final overrides = TestIOOverrides(filePath);
      await IOOverrides.runWithIOOverrides(() async {
        final validator = Validator(
          ruleConfigs: {
            Validator.skillFileInaccessible: const RuleConfig(severity: AnalysisSeverity.warning),
          },
        );
        final ValidationResult validationResult = await validator.validate(skillDir);

        expect(
          validationResult.isValid,
          isTrue,
          reason: '${_describe(validationResult.validationErrors)}',
        );
        expect(
          _describe(validationResult.validationErrors),
          contains(_hasRule(Validator.skillFileInaccessible, severity: AnalysisSeverity.warning)),
        );
      }, overrides);
    });

    test('passes if directory exists and contains SKILL.md', () async {
      final skillDir = Directory(p.join(tempDir.path, 'test-skill'));
      await skillDir.create();
      await File(p.join(skillDir.path, 'SKILL.md')).writeAsString('''
---
name: test-skill
description: A test skill
---
Body''');

      final validator = Validator();
      final ValidationResult result = await validator.validate(skillDir);

      expect(result.isValid, isTrue, reason: result.errors.isEmpty ? '' : result.errors.first);
      expect(result.errors, isEmpty);
    });
  });
}

/// Describes each error as a record so a failed `expect` prints the rule ID,
/// severity, file, and message of every error the validator reported.
List<({String ruleId, AnalysisSeverity severity, String file, String message})> _describe(
  List<ValidationError> errors,
) => [
  for (final e in errors)
    (ruleId: e.ruleId, severity: e.severity, file: e.file, message: e.message),
];

/// Matches a record from [_describe] whose `ruleId` is [ruleId].
Matcher _hasRule(String ruleId, {AnalysisSeverity? severity}) =>
    predicate<({String ruleId, AnalysisSeverity severity, String file, String message})>(
      (e) => e.ruleId == ruleId && (severity == null || e.severity == severity),
      'an error with ruleId $ruleId${severity == null ? '' : ' and severity $severity'}',
    );
