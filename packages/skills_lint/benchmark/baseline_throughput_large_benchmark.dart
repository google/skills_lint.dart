// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:bench_press/bench_press.dart';
import 'package:path/path.dart' as p;
import 'package:skills_lint/skills_lint.dart';

// TODO(reidbaker): https://github.com/google/skills_lint.dart/issues/23 Disable in CI or replace microbenchmark calibration with macro-benchmarking to eliminate latency calibration flakiness.
/// Large-scale benchmark for baseline generation throughput.
///
/// Tests performance and algorithmic scaling across a batch of synthetic skills
/// with baseline-recordable errors across CI runner architectures.
final class BaselineThroughputLargeBenchmark extends AsyncBenchmark {
  BaselineThroughputLargeBenchmark() : super('baseline_throughput_large');

  static const int _skillCount = 60;
  static const int _errorsPerSkill = 1;

  late Directory _tempDir;
  late String _skillsRootPath;
  late String _ignorePath;

  @override
  Throughput get throughput => const Throughput.elements(_skillCount);

  @override
  Future<void> setup() async {
    _tempDir = Directory.systemTemp.createTempSync('skills_lint_bench_large_');
    final skillsRoot = Directory(p.join(_tempDir.path, 'skills'))..createSync();
    _skillsRootPath = skillsRoot.path;
    _ignorePath = p.join(_tempDir.path, 'ignore.json');

    for (var i = 0; i < _skillCount; i++) {
      _writeSyntheticSkill(skillsRoot, i, _errorsPerSkill);
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
    final ignoreFile = File(_ignorePath);
    if (ignoreFile.existsSync()) {
      ignoreFile.deleteSync();
    }

    final bool success = await validateSkills(
      skillDirPaths: <String>[_skillsRootPath],
      generateBaseline: true,
      quiet: true,
      ignoreFileOverride: _ignorePath,
    );
    Blackhole.consume(success);
  }

  void _writeSyntheticSkill(Directory skillsRoot, int index, int errorsPerSkill) {
    final dirName = 'skill-$index';
    final skillDir = Directory(p.join(skillsRoot.path, dirName))..createSync();

    // Error 1: name mismatch triggers `invalid-skill-name`.
    const name = 'wrong-name-on-purpose';

    // Error 2 (when errorsPerSkill >= 2): description > 1024 chars triggers `description-too-long`.
    final String description = errorsPerSkill >= 2
        ? 'x' * 1100
        : 'Synthetic skill for benchmarking; '
              'the yaml name does not match the directory name '
              'so the linter records a name-format error.';

    // Error 3 (when errorsPerSkill >= 3): absolute-path link triggers `check-absolute-paths`.
    final body = errorsPerSkill >= 3
        ? '# Test skill\n\n[abs](${p.absolute('synthetic-abs-path')})\n'
        : '# Test skill\n';

    final sb = StringBuffer()
      ..writeln('---')
      ..writeln('name: $name')
      ..writeln('description: $description')
      ..writeln('---')
      ..writeln()
      ..write(body);

    File(p.join(skillDir.path, 'SKILL.md')).writeAsStringSync(sb.toString());
  }
}

void main(List<String> args) => mainAsyncBenchmark(BaselineThroughputLargeBenchmark(), args);
