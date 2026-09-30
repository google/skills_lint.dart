// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// The benchmark definitions and the loop that runs the CLI and times it.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import 'fixture.dart';

/// How a [Target] runs the CLI.
enum Runtime {
  /// A native executable from `dart compile exe`, which is what
  /// `dart install skills_lint` and the release binaries give users.
  aot,

  /// A kernel file run by the Dart VM. `dart run skills_lint` in a package
  /// that depends on `skills_lint` runs the same kind of file.
  jit,
}

/// A quantity recorded for each run.
enum Metric {
  /// Time from process start to process exit, in milliseconds.
  wallTime('wall time', 'ms'),

  /// Peak resident set size of the process, in MiB.
  peakRss('peak RSS', 'MiB');

  const Metric(this.label, this.unit);

  /// Name shown in reports.
  final String label;

  /// Unit of the values in reports.
  final String unit;
}

/// One benchmark: a fixture, a runtime and fixed run counts.
@immutable
final class BenchmarkDefinition {
  const BenchmarkDefinition({
    required this.name,
    required this.description,
    required this.fixture,
    required this.runtime,
    required this.warmup,
    required this.iterations,
    required this.metrics,
  });

  /// Identifier used in reports and JSON output. Rename the benchmark when
  /// its workload changes, so results under one name stay comparable.
  final String name;

  /// One-line description of the user workflow the benchmark stands for.
  final String description;

  /// The repository the CLI validates.
  final FixtureSpec fixture;

  /// How the CLI runs.
  final Runtime runtime;

  /// Untimed runs per target before the timed runs. They fill the file
  /// cache and page in the executable.
  final int warmup;

  /// Timed runs per target.
  final int iterations;

  /// Metrics that the reports show and compare.
  final Set<Metric> metrics;
}

/// The benchmarks that `run_benchmarks.dart` runs.
const List<BenchmarkDefinition> benchmarks = [
  BenchmarkDefinition(
    name: 'large_repo_aot',
    description: 'Installed executable validating a repository of 1000 skills.',
    fixture: FixtureSpec(skillCount: 1000),
    runtime: Runtime.aot,
    warmup: 2,
    iterations: 15,
    metrics: {Metric.wallTime, Metric.peakRss},
  ),
  BenchmarkDefinition(
    name: 'small_repo_jit',
    description: '`dart run skills_lint` on a repository of 5 skills, as in a pre-commit hook.',
    fixture: FixtureSpec(skillCount: 5),
    runtime: Runtime.jit,
    warmup: 3,
    iterations: 30,
    metrics: {Metric.wallTime},
  ),
];

/// The exit code the CLI returns for every fixture.
///
/// [writeFixture] always plants an error in the first skill, so the CLI
/// reports a lint failure. Any other exit code means the run did not
/// validate the fixture, and its timing is meaningless.
const int expectedExitCode = 1;

/// A build of the CLI to measure.
@immutable
final class Target {
  const Target({required this.label, required this.aotCommand, required this.jitCommand});

  /// Name of the build in reports, such as `baseline` or `candidate`.
  final String label;

  /// Command line that runs the build as a native executable.
  final List<String> aotCommand;

  /// Command line that runs the build on the Dart VM.
  final List<String> jitCommand;

  /// Returns the command line for [runtime].
  List<String> command(Runtime runtime) => switch (runtime) {
    Runtime.aot => aotCommand,
    Runtime.jit => jitCommand,
  };
}

/// The measurements from one run of the CLI.
@immutable
final class RunSample {
  const RunSample({required this.wallTime, this.peakRssBytes});

  /// Time from process start to process exit.
  final Duration wallTime;

  /// Peak resident set size in bytes, or `null` when the platform has no
  /// [RssProbe].
  final int? peakRssBytes;

  /// Returns the value of [metric] in the unit of [Metric.unit], or `null`
  /// when this run did not record it.
  double? value(Metric metric) => switch (metric) {
    Metric.wallTime => wallTime.inMicroseconds / Duration.microsecondsPerMillisecond,
    Metric.peakRss => peakRssBytes == null ? null : peakRssBytes! / (1024 * 1024),
  };
}

/// The runs of one benchmark, keyed by [Target.label].
@immutable
final class BenchmarkResult {
  const BenchmarkResult({required this.definition, required this.samples});

  /// The benchmark that ran.
  final BenchmarkDefinition definition;

  /// Timed runs for each target, in the order they ran.
  final Map<String, List<RunSample>> samples;

  /// Returns the values of [metric] recorded for [label], skipping runs
  /// that did not record it.
  List<double> values(String label, Metric metric) => [
    for (final RunSample sample in samples[label] ?? const []) ?sample.value(metric),
  ];
}

/// Thrown when a run of the CLI does not behave as a benchmark run must.
final class BenchmarkException implements Exception {
  BenchmarkException(this.message);

  /// What went wrong, including the command and its output.
  final String message;
}

/// Records the peak resident set size of a child process with
/// `/usr/bin/time`.
@immutable
final class RssProbe {
  const RssProbe._(this._flag, this._parse);

  /// Path of the `time` utility the probe wraps commands in.
  static const String timePath = '/usr/bin/time';

  /// Returns a probe for the host, or `null` on Windows or when
  /// [timePath] does not exist.
  static RssProbe? detect() {
    if (!File(timePath).existsSync()) {
      return null;
    }
    if (Platform.isLinux) {
      return const RssProbe._('-v', parseGnuTime);
    }
    if (Platform.isMacOS) {
      return const RssProbe._('-l', parseBsdTime);
    }
    return null;
  }

  final String _flag;
  final int? Function(String report) _parse;

  /// Returns [command] wrapped so that `time` writes its report to
  /// [reportPath].
  List<String> wrap(List<String> command, String reportPath) => [
    timePath,
    _flag,
    '-o',
    reportPath,
    ...command,
  ];

  /// Returns the peak resident set size in bytes from the report at
  /// [reportPath], or `null` if the report has none.
  int? read(String reportPath) => _parse(File(reportPath).readAsStringSync());
}

/// Returns the peak resident set size in bytes from the output of GNU
/// `time -v`, or `null` if [report] does not contain it.
int? parseGnuTime(String report) {
  final RegExpMatch? match = RegExp(
    r'Maximum resident set size \(kbytes\): (\d+)',
  ).firstMatch(report);
  return match == null ? null : int.parse(match.group(1)!) * 1024;
}

/// Returns the peak resident set size in bytes from the output of BSD
/// `time -l`, or `null` if [report] does not contain it.
int? parseBsdTime(String report) {
  final RegExpMatch? match = RegExp(r'(\d+)\s+maximum resident set size').firstMatch(report);
  return match == null ? null : int.parse(match.group(1)!);
}

/// Runs [definition] against every target in [targets].
///
/// Runs happen in [workingDirectory], which must hold the fixture for
/// [BenchmarkDefinition.fixture]. The targets take turns, and the order
/// reverses on every round (A B, B A, A B, ...), so drift in machine speed
/// affects every target alike. [scratchDirectory] holds the `time` reports.
///
/// Throws [BenchmarkException] if a run exits with a code other than
/// [expectedExitCode].
Future<BenchmarkResult> runBenchmark(
  BenchmarkDefinition definition,
  List<Target> targets, {
  required String workingDirectory,
  required String scratchDirectory,
  RssProbe? rssProbe,
}) async {
  final runner = _Runner(workingDirectory, p.join(scratchDirectory, 'time-report.txt'), rssProbe);
  final Map<String, List<RunSample>> samples = {for (final t in targets) t.label: []};
  final int rounds = definition.warmup + definition.iterations;
  for (var round = 0; round < rounds; round++) {
    final Iterable<Target> order = round.isEven ? targets : targets.reversed;
    for (final target in order) {
      final RunSample sample = await runner.run(target.command(definition.runtime));
      if (round >= definition.warmup) {
        samples[target.label]!.add(sample);
      }
    }
  }
  return BenchmarkResult(definition: definition, samples: samples);
}

final class _Runner {
  _Runner(this.workingDirectory, this.reportPath, this.rssProbe);

  final String workingDirectory;
  final String reportPath;
  final RssProbe? rssProbe;

  Future<RunSample> run(List<String> command) async {
    final reportFile = File(reportPath);
    if (reportFile.existsSync()) {
      reportFile.deleteSync();
    }
    final List<String> full = rssProbe?.wrap(command, reportPath) ?? command;
    final stopwatch = Stopwatch()..start();
    final Process process = await Process.start(
      full.first,
      full.sublist(1),
      workingDirectory: workingDirectory,
    );
    // Read both pipes as they fill so the child never blocks on a full pipe.
    final Future<List<int>> stdoutBytes = _collect(process.stdout);
    final Future<List<int>> stderrBytes = _collect(process.stderr);
    final int exitCode = await process.exitCode;
    stopwatch.stop();
    final List<int> out = await stdoutBytes;
    final List<int> err = await stderrBytes;
    if (exitCode != expectedExitCode) {
      throw BenchmarkException(
        '`${command.join(' ')}` in $workingDirectory exited with $exitCode, '
        'expected $expectedExitCode.\n${_tail(out)}\n${_tail(err)}',
      );
    }
    return RunSample(wallTime: stopwatch.elapsed, peakRssBytes: rssProbe?.read(reportPath));
  }

  static Future<List<int>> _collect(Stream<List<int>> stream) =>
      stream.fold(<int>[], (bytes, chunk) => bytes..addAll(chunk));

  static String _tail(List<int> bytes) {
    const maxBytes = 2000;
    final List<int> tail = bytes.length > maxBytes ? bytes.sublist(bytes.length - maxBytes) : bytes;
    return utf8.decode(tail, allowMalformed: true);
  }
}
