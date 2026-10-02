// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Times each skills_lint rule on its own, in process, through the public
/// `Validator` and `SkillRule` API.
library;

import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:skills_lint/skills_lint.dart';

import 'fixture.dart';

/// Directories, relative to the repository root, whose skills make up the
/// real corpus.
const List<String> realCorpusRoots = [
  'third_party/skill-repos',
  '.agents/skills',
  'packages/skills_lint/skills',
];

/// Untimed passes over the corpus before the timed ones.
const int timingWarmup = 3;

/// Timed samples per rule.
const int timingRepetitions = 15;

/// Each sample visits at least this many skills, repeating a small corpus,
/// so that a sample on a few dozen skills is long enough to time.
const int minimumSkillVisits = 1000;

/// Returns every directory under [roots] that holds a `SKILL.md`, sorted by
/// path. Roots that don't exist are skipped.
List<Directory> findSkillDirectories(Iterable<String> roots) {
  final dirs = <String>{};
  for (final root in roots) {
    final directory = Directory(root);
    if (!directory.existsSync()) {
      continue;
    }
    for (final File file in directory.listSync(recursive: true).whereType<File>()) {
      if (p.basename(file.path) == SkillContext.skillFileName) {
        dirs.add(file.parent.path);
      }
    }
  }
  return [for (final path in dirs.toList()..sort()) Directory(path)];
}

/// The rule configuration of the benchmark fixture, [fixtureConfig], as
/// `Validator` input.
///
/// Throws [StateError] if the configuration doesn't parse or a rule has no
/// severity.
Map<String, RuleConfig> timedRuleConfigs([String config = fixtureConfig]) {
  final Configuration parsed = ConfigParser.parse(config);
  if (parsed.parsingErrors.isNotEmpty) {
    throw StateError('The fixture configuration does not parse: ${parsed.parsingErrors}');
  }
  return {
    for (final MapEntry(key: name, value: patch) in parsed.ruleConfigs.entries)
      name: RuleConfig(
        severity: patch.severity ?? (throw StateError('Rule $name has no severity')),
        parameters: patch.parameters,
      ),
  };
}

/// How many times a sample repeats a corpus of [skillCount] skills to visit
/// at least [minimumSkillVisits] skills.
int loopsFor(int skillCount) {
  if (skillCount < 1) {
    throw ArgumentError.value(skillCount, 'skillCount', 'must be at least 1');
  }
  return (minimumSkillVisits / skillCount).ceil();
}

/// The time each rule took on one corpus.
@immutable
final class CorpusTimings {
  const CorpusTimings({required this.corpus, required this.skillCount, required this.rules});

  /// Name of the corpus, such as `fixture` or `real`.
  final String corpus;

  /// Number of skills in the corpus.
  final int skillCount;

  /// Microseconds per skill for each rule, one sample per repetition,
  /// keyed by rule name.
  final Map<String, List<double>> rules;

  Map<String, Object?> toJson() => {
    TimingJsonKeys.corpus: corpus,
    TimingJsonKeys.skillCount: skillCount,
    TimingJsonKeys.rules: {
      for (final MapEntry(key: name, value: samples) in rules.entries) name: samples,
    },
  };

  /// Reads the output of [toJson].
  static CorpusTimings fromJson(Map<String, Object?> json) => CorpusTimings(
    corpus: json[TimingJsonKeys.corpus]! as String,
    skillCount: json[TimingJsonKeys.skillCount]! as int,
    rules: {
      for (final MapEntry(key: name, value: samples)
          in (json[TimingJsonKeys.rules]! as Map<String, Object?>).entries)
        name: [for (final s in samples! as List<Object?>) (s! as num).toDouble()],
    },
  );
}

/// Keys of the timings JSON report.
abstract final class TimingJsonKeys {
  static const String corpora = 'corpora';
  static const String corpus = 'corpus';
  static const String skillCount = 'skill_count';
  static const String rules = 'rules';
}

/// Times each rule of [validator] on the skills in [dirs].
///
/// Reads and parses each skill once. Each sample runs one rule over the
/// parsed skills [loopsFor] times. Samples of different rules take turns, so
/// machine drift hits every rule alike.
Future<CorpusTimings> timeRules(
  String corpus,
  List<Directory> dirs,
  Validator validator, {
  int warmup = timingWarmup,
  int repetitions = timingRepetitions,
}) async {
  final List<SkillRule> rules = validator.rules;
  final parser = Validator(
    ruleConfigs: {
      for (final rule in rules) rule.name: const RuleConfig(severity: AnalysisSeverity.disabled),
    },
  );
  final contexts = <SkillContext>[for (final dir in dirs) (await parser.validate(dir)).context!];
  final int loops = loopsFor(contexts.length);
  final int visits = loops * contexts.length;
  final samples = <String, List<double>>{for (final rule in rules) rule.name: []};
  final stopwatch = Stopwatch();
  for (var round = 0; round < warmup + repetitions; round++) {
    for (final rule in rules) {
      stopwatch
        ..reset()
        ..start();
      for (var loop = 0; loop < loops; loop++) {
        for (final context in contexts) {
          await rule.validate(context);
        }
      }
      stopwatch.stop();
      if (round >= warmup) {
        samples[rule.name]!.add(stopwatch.elapsedMicroseconds / visits);
      }
    }
  }
  return CorpusTimings(corpus: corpus, skillCount: contexts.length, rules: samples);
}
