// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../benchmark/src/fixture.dart';
import '../../benchmark/src/suite.dart';

/// A script that appends its second argument to the file named by its first
/// argument and exits with its third argument.
const String _probeScript = r'''
import 'dart:io';

void main(List<String> args) {
  File(args[0]).writeAsStringSync('${args[1]}\n', mode: FileMode.append);
  exitCode = int.parse(args[2]);
}
''';

BenchmarkDefinition _definition({int warmup = 0, int iterations = 1}) => BenchmarkDefinition(
  name: 'test',
  description: 'Test benchmark.',
  skillCount: 3,
  warmup: warmup,
  iterations: iterations,
  metrics: const {Metric.wallTime, Metric.peakRss},
);

void main() {
  test('the benchmarks have unique names and at least one timed run', () {
    expect(benchmarks.map((b) => b.name).toSet(), hasLength(benchmarks.length));
    for (final BenchmarkDefinition b in benchmarks) {
      expect(b.iterations, greaterThan(0), reason: b.name);
      expect(b.metrics, contains(Metric.wallTime), reason: b.name);
    }
  });

  group('time report parsing', () {
    test('reads the peak RSS from GNU time -v in kilobytes', () {
      const report = '''
	Command exited with non-zero status 1
	Maximum resident set size (kbytes): 71234
	Average resident set size (kbytes): 0
''';
      expect(parseGnuTime(report), 71234 * 1024);
    });

    test('reads the peak RSS from BSD time -l in bytes', () {
      const report = '''
        0.50 real         0.32 user         0.11 sys
            73859072  maximum resident set size
                   0  average shared memory size
''';
      expect(parseBsdTime(report), 73859072);
    });

    test('returns null when the report has no peak RSS', () {
      expect(parseGnuTime('no data'), isNull);
      expect(parseBsdTime('no data'), isNull);
    });
  });

  test('RunSample reports wall time in milliseconds and RSS in MiB', () {
    const sample = RunSample(wallTime: Duration(microseconds: 1500), peakRssBytes: 3 * 1024 * 1024);

    expect(sample.value(Metric.wallTime), 1.5);
    expect(sample.value(Metric.peakRss), 3);
    expect(const RunSample(wallTime: Duration.zero).value(Metric.peakRss), isNull);
  });

  group('runBenchmark', () {
    late Directory tempDir;
    late String probe;
    late String log;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('suite_test.');
      probe = p.join(tempDir.path, 'probe.dart');
      File(probe).writeAsStringSync(_probeScript);
      log = p.join(tempDir.path, 'log.txt');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    Target probeTarget(String label, {int exit = expectedExitCode}) =>
        Target(label: label, command: [Platform.resolvedExecutable, probe, log, label, '$exit']);

    test('alternates the target order each round and keeps only timed runs', () async {
      final BenchmarkResult result = await runBenchmark(
        _definition(warmup: 1, iterations: 2),
        [probeTarget('a'), probeTarget('b')],
        workingDirectory: tempDir.path,
        scratchDirectory: tempDir.path,
      );

      expect(File(log).readAsLinesSync(), ['a', 'b', 'b', 'a', 'a', 'b']);
      expect(result.samples['a'], hasLength(2));
      expect(result.samples['b'], hasLength(2));
      expect(result.values('a', Metric.wallTime).every((ms) => ms > 0), isTrue);
    });

    test('throws when a run exits with an unexpected code', () async {
      await expectLater(
        runBenchmark(
          _definition(),
          [probeTarget('a', exit: 0)],
          workingDirectory: tempDir.path,
          scratchDirectory: tempDir.path,
        ),
        throwsA(
          isA<BenchmarkException>().having((e) => e.message, 'message', contains('exited with 0')),
        ),
      );
    });

    test('the CLI reports a lint failure on a generated fixture', () async {
      final String fixture = p.join(tempDir.path, 'fixture');
      writeFixture(fixture, 3);
      final String cli = p.absolute('bin', 'skills_lint.dart');
      final RssProbe? rssProbe = RssProbe.detect();

      final BenchmarkResult result = await runBenchmark(
        _definition(),
        [
          Target(label: 'cli', command: [Platform.resolvedExecutable, cli]),
        ],
        workingDirectory: fixture,
        scratchDirectory: tempDir.path,
        rssProbe: rssProbe,
      );

      expect(result.samples['cli'], hasLength(1));
      if (rssProbe != null) {
        expect(result.values('cli', Metric.peakRss).single, greaterThan(1));
      }
    });
  });
}
