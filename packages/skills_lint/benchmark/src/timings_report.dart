// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Comparison of two builds' rule timings and the Markdown report.
library;

import 'package:meta/meta.dart';

import 'format.dart';
import 'stats.dart';
import 'timings.dart';

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

  /// Name of the rule.
  final String rule;

  /// Whether the rule was measured in both builds.
  final RuleStatus status;

  /// Candidate samples, in microseconds per skill. Null for a removed rule.
  final Summary? candidate;

  /// Baseline samples, in microseconds per skill. Null without a baseline or
  /// for an added rule.
  final Summary? baseline;

  /// The candidate median as a fraction of the sum of candidate medians.
  final double? share;

  /// Change of the median from baseline to candidate, as a fraction of the
  /// baseline median.
  double? get change => relativeChange(baseline?.median, candidate?.median);
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
        share: total == 0 ? 0 : summary.median / total,
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
    final String candidateCell = formatNumber(row.candidate?.median);
    final String share = row.share == null ? '' : formatPercent(row.share!);
    final String mad = row.candidate == null ? '' : formatPercent(row.candidate!.madPercent / 100);
    if (compared) {
      buffer.writeln(
        '| ${row.rule} | $onByDefault | ${formatNumber(row.baseline?.median)} | $candidateCell | '
        '${_changeCell(row)} | $share | $mad |',
      );
    } else {
      buffer.writeln('| ${row.rule} | $onByDefault | $candidateCell | $share | $mad |');
    }
  }
}

String _changeCell(RuleTimingRow row) => switch (row.status) {
  RuleStatus.added => '**new rule**',
  RuleStatus.removed => 'removed',
  RuleStatus.measured => switch (row.change) {
    null => '',
    final double change => formatSignedPercent(change),
  },
};
