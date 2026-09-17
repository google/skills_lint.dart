// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:bench_press/bench_press.dart';
import 'package:path/path.dart' as p;
import 'package:skills_lint/skills_lint.dart';

/// Benchmark for full validation throughput across valid and invalid skills.
///
/// Measures the rate at which `validateSkills` executes lint rules across
/// a realistic batch of skill directories without baseline generation.
final class LintValidationBenchmark extends AsyncBenchmark {
  LintValidationBenchmark() : super('lint_validation');

  static const int _validCount = 25;
  static const int _invalidCount = 25;
  static const int _totalCount = _validCount + _invalidCount;

  late Directory _tempDir;
  late String _skillsRootPath;

  @override
  Throughput get throughput => const Throughput.elements(_totalCount);

  @override
  Future<void> setup() async {
    _tempDir = Directory.systemTemp.createTempSync('skills_lint_val_bench_');
    final skillsRoot = Directory(p.join(_tempDir.path, 'skills'))..createSync();
    _skillsRootPath = skillsRoot.path;

    // Create valid skills
    for (var i = 0; i < _validCount; i++) {
      final name = 'valid-skill-$i';
      final skillDir = Directory(p.join(skillsRoot.path, name))..createSync();
      final content =
          '''
---
name: $name
description: A valid skill for testing validation throughput and linter performance.
---

# $name

Instructions for $name.
''';
      File(p.join(skillDir.path, 'SKILL.md')).writeAsStringSync(content);
    }

    // Create invalid skills
    for (var i = 0; i < _invalidCount; i++) {
      final dirName = 'invalid-skill-$i';
      final skillDir = Directory(p.join(skillsRoot.path, dirName))..createSync();
      final content =
          '''
---
name: mismatched-name-$i
description: ${'x' * 1100}
---

# Invalid Skill

[link](${p.absolute('non-existent-target')})
''';
      File(p.join(skillDir.path, 'SKILL.md')).writeAsStringSync(content);
    }
  }

  @override
  Future<void> teardown() async {
    if (_tempDir.existsSync()) {
      _tempDir.deleteSync(recursive: true);
    }
  }

  @override
  Future<void> run() async {
    final bool success = await validateSkills(
      skillDirPaths: <String>[_skillsRootPath],
      quiet: true,
    );
    Blackhole.consume(success);
  }
}

void main(List<String> args) => mainAsyncBenchmark(LintValidationBenchmark(), args);
