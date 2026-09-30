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
import 'stats.dart';

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

/// Whether a rule was measured in both builds or in only one.
enum RuleStatus { measured, added, removed }

/// One row of the timings report.
@immutable
final class RuleTimingRow {
  const RuleTimingRow({
    required this.rule,
    required this.status,
    this.candidate,
    this.baseline,
    this.share,
  });

  final String rule;
  final RuleStatus status;

  /// Candidate samples, in microseconds per skill. Null for a removed rule.
  final Summary? candidate;

  /// Baseline samples, in microseconds per skill. Null without a baseline or
  /// for an added rule.
  final Summary? baseline;

  /// The candidate median as a percentage of the sum of candidate medians.
  final double? share;

  /// Change of the median from baseline to candidate, in percent.
  double? get change {
    final double? before = baseline?.median;
    final double? after = candidate?.median;
    if (before == null || after == null || before == 0) {
      return null;
    }
    return (after - before) / before * 100;
  }
}

/// Lines up the rules of [candidate] and [baseline], costliest candidate
/// rule first, then rules that only [baseline] has.
///
/// Without a [baseline] every candidate rule has status
/// [RuleStatus.measured]. With one, a rule only in [candidate] is
/// [RuleStatus.added].
List<RuleTimingRow> compareTimings(CorpusTimings candidate, {CorpusTimings? baseline}) {
  final Map<String, Summary> after = {
    for (final MapEntry(key: name, value: samples) in candidate.rules.entries)
      name: Summary.of(samples),
  };
  final Map<String, Summary> before = {
    for (final MapEntry(key: name, value: samples) in (baseline?.rules ?? {}).entries)
      name: Summary.of(samples),
  };
  final double total = after.values.fold(0, (sum, s) => sum + s.median);
  final List<RuleTimingRow> rows = [
    for (final MapEntry(key: name, value: summary) in after.entries)
      RuleTimingRow(
        rule: name,
        status: baseline != null && !before.containsKey(name)
            ? RuleStatus.added
            : RuleStatus.measured,
        candidate: summary,
        baseline: before[name],
        share: total == 0 ? 0 : summary.median / total * 100,
      ),
  ]..sort((a, b) => b.candidate!.median.compareTo(a.candidate!.median));
  final List<String> removed = [
    for (final name in before.keys)
      if (!after.containsKey(name)) name,
  ]..sort();
  return [
    ...rows,
    for (final name in removed)
      RuleTimingRow(rule: name, status: RuleStatus.removed, baseline: before[name]),
  ];
}

/// Renders the timings of each corpus in [candidate] as Markdown, compared
/// with the corpus of the same name in [baseline] when given.
///
/// [defaultRules] names the rules that are on without configuration.
String timingsMarkdown(
  List<CorpusTimings> candidate, {
  List<CorpusTimings>? baseline,
  Set<String> defaultRules = const {},
}) {
  final buffer = StringBuffer()
    ..writeln('## Rule timings')
    ..writeln()
    ..writeln(
      'Each rule runs alone over skills that are already read and parsed. '
      'Times are medians of $timingRepetitions samples, in microseconds per skill. '
      'This report is for information: it never fails the job.',
    );
  for (final corpus in candidate) {
    final CorpusTimings? before = baseline?.where((b) => b.corpus == corpus.corpus).firstOrNull;
    _writeCorpus(buffer, corpus, before, defaultRules, hasBaseline: baseline != null);
  }
  return buffer.toString();
}

void _writeCorpus(
  StringBuffer buffer,
  CorpusTimings corpus,
  CorpusTimings? baseline,
  Set<String> defaultRules, {
  required bool hasBaseline,
}) {
  buffer
    ..writeln()
    ..writeln('### ${corpus.corpus} (${corpus.skillCount} skills)')
    ..writeln();
  if (hasBaseline && baseline == null) {
    buffer
      ..writeln('The baseline has no timings for this corpus.')
      ..writeln();
  }
  final compared = baseline != null;
  buffer
    ..writeln(
      compared
          ? '| Rule | On by default | Baseline µs/skill | Candidate µs/skill | Change | Share | MAD |'
          : '| Rule | On by default | µs/skill | Share | MAD |',
    )
    ..writeln(
      compared
          ? '| --- | --- | ---: | ---: | ---: | ---: | ---: |'
          : '| --- | --- | ---: | ---: | ---: |',
    );
  for (final RuleTimingRow row in compareTimings(corpus, baseline: baseline)) {
    final onByDefault = defaultRules.contains(row.rule) ? 'yes' : 'no';
    final String candidateCell = _micros(row.candidate?.median);
    final share = row.share == null ? '' : '${row.share!.toStringAsFixed(1)}%';
    final mad = row.candidate == null ? '' : '${row.candidate!.madPercent.toStringAsFixed(1)}%';
    if (compared) {
      buffer.writeln(
        '| ${row.rule} | $onByDefault | ${_micros(row.baseline?.median)} | $candidateCell | '
        '${_changeCell(row)} | $share | $mad |',
      );
    } else {
      buffer.writeln('| ${row.rule} | $onByDefault | $candidateCell | $share | $mad |');
    }
  }
}

String _micros(double? value) => value == null ? '' : value.toStringAsFixed(1);

String _changeCell(RuleTimingRow row) => switch (row.status) {
  RuleStatus.added => '**new rule**',
  RuleStatus.removed => 'removed',
  RuleStatus.measured => switch (row.change) {
    null => '',
    final double change => '${change >= 0 ? '+' : ''}${change.toStringAsFixed(1)}%',
  },
};
