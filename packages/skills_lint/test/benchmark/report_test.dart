// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:test/test.dart';

import '../../benchmark/src/fixture.dart';
import '../../benchmark/src/report.dart';
import '../../benchmark/src/suite.dart';

const BenchmarkDefinition _definition = BenchmarkDefinition(
  name: 'example',
  description: 'An example benchmark.',
  fixture: FixtureSpec(skillCount: 3),
  runtime: Runtime.aot,
  warmup: 0,
  iterations: 3,
  metrics: {Metric.wallTime, Metric.peakRss},
);

/// Returns runs with the given wall times in milliseconds and RSS in MiB.
List<RunSample> _runs(List<int> millis, {int? rssMib}) => [
  for (final ms in millis)
    RunSample(
      wallTime: Duration(milliseconds: ms),
      peakRssBytes: rssMib == null ? null : rssMib * 1024 * 1024,
    ),
];

BenchmarkResult _result({required List<int> baseline, required List<int> candidate, int? rssMib}) =>
    BenchmarkResult(
      definition: _definition,
      samples: {
        'baseline': _runs(baseline, rssMib: rssMib),
        'candidate': _runs(candidate, rssMib: rssMib),
      },
    );

List<Comparison> _compare(BenchmarkResult result) =>
    compare([result], baseline: 'baseline', candidate: 'candidate');

void main() {
  group('compare', () {
    test('compares the medians of each metric that both targets recorded', () {
      final List<Comparison> comparisons = _compare(
        _result(baseline: [90, 100, 500], candidate: [110, 120, 130], rssMib: 64),
      );

      expect(comparisons, hasLength(2));
      final Comparison time = comparisons.singleWhere((c) => c.metric == Metric.wallTime);
      expect(time.benchmark, 'example');
      expect(time.baseline.median, 100);
      expect(time.candidate.median, 120);
      expect(time.change, closeTo(0.2, 1e-9));
      expect(time.isRegression, isFalse);
      final Comparison rss = comparisons.singleWhere((c) => c.metric == Metric.peakRss);
      expect(rss.change, 0);
    });

    test('flags a change above the metric threshold only', () {
      final double threshold = regressionThresholds[Metric.wallTime]!;
      final int atThreshold = (100 * (1 + threshold)).round();

      expect(
        _compare(_result(baseline: [100], candidate: [atThreshold])).single.isRegression,
        isFalse,
      );
      expect(
        _compare(_result(baseline: [100], candidate: [atThreshold + 1])).single.isRegression,
        isTrue,
      );
    });

    test('does not flag an improvement', () {
      final Comparison c = _compare(_result(baseline: [200], candidate: [100])).single;

      expect(c.change, -0.5);
      expect(c.isRegression, isFalse);
    });

    test('skips metrics that a target did not record', () {
      final List<Comparison> comparisons = _compare(_result(baseline: [1], candidate: [1]));

      expect(comparisons.map((c) => c.metric), [Metric.wallTime]);
    });

    test('skips a target that is missing', () {
      final result = BenchmarkResult(
        definition: _definition,
        samples: {
          'candidate': _runs([1]),
        },
      );

      expect(_compare(result), isEmpty);
    });
  });

  group('regressionAnnotations', () {
    test('emits a GitHub warning for each regression only', () {
      final List<Comparison> comparisons = [
        ..._compare(_result(baseline: [100], candidate: [200])),
        ..._compare(_result(baseline: [100], candidate: [101])),
      ];

      final List<String> annotations = regressionAnnotations(comparisons);

      expect(annotations, hasLength(1));
      expect(annotations.single, startsWith('::warning title=Possible benchmark regression::'));
      expect(
        annotations.single,
        contains('example wall time median rose 100.0% (100.0 -> 200.0 ms)'),
      );
    });
  });

  group('markdownReport', () {
    test('lists every target and metric, the comparison and the environment', () {
      final BenchmarkResult result = _result(
        baseline: [100, 100, 100],
        candidate: [150, 150, 150],
        rssMib: 64,
      );

      final String markdown = markdownReport(
        [result],
        labels: ['baseline', 'candidate'],
        comparisons: _compare(result),
        environment: {'OS': 'TestOS'},
      );

      expect(markdown, contains('- OS: TestOS'));
      expect(
        markdown,
        contains(
          '| example | wall time (ms) | baseline | 3 | 100.0 | 100.0 | 100.0 | 100.0 | 0.0 (0.0%) |',
        ),
      );
      expect(markdown, contains('| example | peak RSS (MiB) | candidate | 3 | 64.0 |'));
      expect(
        markdown,
        contains(
          '| example | wall time (ms) | 100.0 | 150.0 | +50.0% | 25.0% | possible regression |',
        ),
      );
      expect(markdown, contains('| example | peak RSS (MiB) | 64.0 | 64.0 | +0.0% | 10.0% | ok |'));
      expect(markdown, contains('- `example`: An example benchmark.'));
    });

    test('leaves out the comparison table without comparisons', () {
      final String markdown = markdownReport(
        [
          _result(baseline: [1], candidate: [1]),
        ],
        labels: ['candidate'],
        comparisons: const [],
        environment: const {},
      );

      expect(markdown, isNot(contains('compared with baseline')));
      expect(markdown, isNot(contains('| baseline |')));
    });
  });

  group('jsonReport', () {
    test('records samples, summaries and comparisons', () {
      final BenchmarkResult result = _result(baseline: [100, 110, 120], candidate: [200, 210, 220]);

      final Map<String, Object?> json = jsonReport(
        [result],
        comparisons: _compare(result),
        environment: {'OS': 'TestOS'},
      );
      final decoded = jsonDecode(jsonEncode(json)) as Map<String, Object?>;

      expect(decoded[JsonKeys.environment], {'OS': 'TestOS'});
      final benchmark =
          (decoded[JsonKeys.benchmarks]! as List<Object?>).single! as Map<String, Object?>;
      expect(benchmark[JsonKeys.name], 'example');
      expect(benchmark[JsonKeys.runtime], 'aot');
      expect(benchmark[JsonKeys.skillCount], 3);
      final metrics = benchmark[JsonKeys.metrics]! as Map<String, Object?>;
      expect(metrics.keys, unorderedEquals(['wallTime', 'peakRss']));
      final wall = metrics['wallTime']! as Map<String, Object?>;
      final targets = wall[JsonKeys.targets]! as Map<String, Object?>;
      final candidate = targets['candidate']! as Map<String, Object?>;
      expect(candidate[JsonKeys.samples], [200, 210, 220]);
      expect((candidate[JsonKeys.summary]! as Map<String, Object?>)[JsonKeys.median], 210);
      expect((metrics['peakRss']! as Map<String, Object?>)[JsonKeys.targets], isEmpty);
      final comparison =
          (decoded[JsonKeys.comparisons]! as List<Object?>).single! as Map<String, Object?>;
      expect(comparison[JsonKeys.metric], 'wallTime');
      expect(comparison[JsonKeys.regression], isTrue);
    });
  });
}
