// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Comparison of two builds and the Markdown and JSON reports.
library;

import 'package:meta/meta.dart';

import 'stats.dart';
import 'suite.dart';

/// Increase in a metric's median that the report flags as a possible
/// regression.
///
/// Each value is a unitless fraction of the baseline median: `0.15` means a
/// candidate median 15% above the baseline median, whether the metric is
/// wall time in milliseconds or peak RSS in MiB.
///
/// Each threshold is several times the run-to-run spread of the median
/// measured with both targets built from the same commit, so noise alone
/// does not cross it. `benchmark/README.md` records the measurements.
const Map<Metric, double> regressionThresholds = {Metric.wallTime: 0.15, Metric.peakRss: 0.10};

/// The medians of one metric for a baseline and a candidate build.
@immutable
final class Comparison {
  const Comparison({
    required this.benchmark,
    required this.metric,
    required this.baseline,
    required this.candidate,
  });

  /// [BenchmarkDefinition.name] of the benchmark.
  final String benchmark;

  /// The compared metric.
  final Metric metric;

  /// Summary of the baseline build's runs.
  final Summary baseline;

  /// Summary of the candidate build's runs.
  final Summary candidate;

  /// Change of the candidate median relative to the baseline median.
  /// Positive values mean the candidate is slower or uses more memory.
  double get change => candidate.median / baseline.median - 1;

  /// The threshold from [regressionThresholds] for [metric].
  double get threshold => regressionThresholds[metric]!;

  /// Whether [change] exceeds [threshold].
  bool get isRegression => change > threshold;
}

/// Compares the [baseline] and [candidate] targets on every metric that
/// both recorded.
List<Comparison> compare(
  List<BenchmarkResult> results, {
  required String baseline,
  required String candidate,
}) => [
  for (final result in results)
    for (final Metric metric in result.definition.metrics)
      if (result.values(baseline, metric).isNotEmpty && result.values(candidate, metric).isNotEmpty)
        Comparison(
          benchmark: result.definition.name,
          metric: metric,
          baseline: Summary.of(result.values(baseline, metric)),
          candidate: Summary.of(result.values(candidate, metric)),
        ),
];

/// Returns a GitHub Actions `::warning::` workflow command for each
/// regression in [comparisons].
List<String> regressionAnnotations(List<Comparison> comparisons) => [
  for (final c in comparisons)
    if (c.isRegression) _annotation(c),
];

String _annotation(Comparison c) =>
    '::warning title=Possible benchmark regression::${c.benchmark} ${c.metric.label} median '
    'rose ${_percent(c.change)} (${_value(c.baseline.median)} -> '
    '${_value(c.candidate.median)} ${c.metric.unit}); the threshold is '
    '${_percent(c.threshold)}. Rerun the benchmarks workflow to confirm before investigating.';

/// Returns a Markdown report of [results] and [comparisons].
///
/// [labels] orders the targets in the tables. [environment] lists facts
/// about the machine, such as the OS and Dart version.
String markdownReport(
  List<BenchmarkResult> results, {
  required List<String> labels,
  required List<Comparison> comparisons,
  required Map<String, String> environment,
}) {
  final buffer = StringBuffer()
    ..writeln('## skills_lint benchmarks')
    ..writeln();
  for (final MapEntry(:key, :value) in environment.entries) {
    buffer.writeln('- $key: $value');
  }
  buffer
    ..writeln()
    ..writeln('| Benchmark | Metric | Build | Runs | Min | Median | p90 | Max | MAD |')
    ..writeln('| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |');
  for (final result in results) {
    for (final Metric metric in result.definition.metrics) {
      for (final label in labels) {
        final List<double> values = result.values(label, metric);
        if (values.isNotEmpty) {
          buffer.writeln(_summaryRow(result.definition.name, metric, label, Summary.of(values)));
        }
      }
    }
  }
  if (comparisons.isNotEmpty) {
    _writeComparisons(buffer, comparisons);
  }
  buffer
    ..writeln()
    ..writeln('Benchmarks:');
  for (final result in results) {
    buffer.writeln('- `${result.definition.name}`: ${result.definition.description}');
  }
  return buffer.toString();
}

/// Returns a JSON-encodable report of [results] and [comparisons].
Map<String, Object?> jsonReport(
  List<BenchmarkResult> results, {
  required List<Comparison> comparisons,
  required Map<String, String> environment,
}) => {
  JsonKeys.environment: environment,
  JsonKeys.benchmarks: [for (final result in results) _benchmarkJson(result)],
  JsonKeys.comparisons: [
    for (final c in comparisons)
      {
        JsonKeys.benchmark: c.benchmark,
        JsonKeys.metric: c.metric.name,
        JsonKeys.baselineMedian: c.baseline.median,
        JsonKeys.candidateMedian: c.candidate.median,
        JsonKeys.change: c.change,
        JsonKeys.threshold: c.threshold,
        JsonKeys.regression: c.isRegression,
      },
  ],
};

/// Keys of the JSON report.
abstract final class JsonKeys {
  static const String environment = 'environment';
  static const String benchmarks = 'benchmarks';
  static const String comparisons = 'comparisons';

  static const String name = 'name';
  static const String description = 'description';
  static const String skillCount = 'skill_count';
  static const String seed = 'seed';
  static const String warmup = 'warmup';
  static const String iterations = 'iterations';
  static const String metrics = 'metrics';
  static const String unit = 'unit';
  static const String targets = 'targets';
  static const String samples = 'samples';
  static const String summary = 'summary';

  static const String count = 'count';
  static const String min = 'min';
  static const String median = 'median';
  static const String p90 = 'p90';
  static const String max = 'max';
  static const String mad = 'mad';

  static const String benchmark = 'benchmark';
  static const String metric = 'metric';
  static const String baselineMedian = 'baseline_median';
  static const String candidateMedian = 'candidate_median';
  static const String change = 'change';
  static const String threshold = 'threshold';
  static const String regression = 'regression';
}

Map<String, Object?> _benchmarkJson(BenchmarkResult result) {
  final BenchmarkDefinition definition = result.definition;
  return {
    JsonKeys.name: definition.name,
    JsonKeys.description: definition.description,
    JsonKeys.skillCount: definition.fixture.skillCount,
    JsonKeys.seed: definition.fixture.seed,
    JsonKeys.warmup: definition.warmup,
    JsonKeys.iterations: definition.iterations,
    JsonKeys.metrics: {
      for (final Metric metric in definition.metrics)
        metric.name: {
          JsonKeys.unit: metric.unit,
          JsonKeys.targets: {
            for (final String label in result.samples.keys)
              if (result.values(label, metric) case final values when values.isNotEmpty)
                label: {
                  JsonKeys.samples: values,
                  JsonKeys.summary: _summaryJson(Summary.of(values)),
                },
          },
        },
    },
  };
}

Map<String, Object?> _summaryJson(Summary s) => {
  JsonKeys.count: s.count,
  JsonKeys.min: s.min,
  JsonKeys.median: s.median,
  JsonKeys.p90: s.p90,
  JsonKeys.max: s.max,
  JsonKeys.mad: s.mad,
};

String _summaryRow(String benchmark, Metric metric, String label, Summary s) =>
    '| $benchmark | ${metric.label} (${metric.unit}) | $label | ${s.count} | ${_value(s.min)} | '
    '${_value(s.median)} | ${_value(s.p90)} | ${_value(s.max)} | '
    '${_value(s.mad)} (${s.madPercent.toStringAsFixed(1)}%) |';

void _writeComparisons(StringBuffer buffer, List<Comparison> comparisons) {
  buffer
    ..writeln()
    ..writeln('### Candidate compared with baseline')
    ..writeln()
    ..writeln(
      '| Benchmark | Metric | Baseline median | Candidate median | Change | Threshold | Result |',
    )
    ..writeln('| --- | --- | ---: | ---: | ---: | ---: | --- |');
  for (final c in comparisons) {
    buffer.writeln(
      '| ${c.benchmark} | ${c.metric.label} (${c.metric.unit}) | ${_value(c.baseline.median)} | '
      '${_value(c.candidate.median)} | ${_signedPercent(c.change)} | ${_percent(c.threshold)} | '
      '${c.isRegression ? 'possible regression' : 'ok'} |',
    );
  }
}

String _value(double v) => v.toStringAsFixed(1);

String _percent(double fraction) => '${(fraction * 100).toStringAsFixed(1)}%';

String _signedPercent(double fraction) => '${fraction >= 0 ? '+' : ''}${_percent(fraction)}';
