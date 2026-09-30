// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Runs the skills_lint macro benchmarks and prints a Markdown report.
///
/// See `README.md` in this directory for usage and for how to read the
/// report.
library;

import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import 'src/fixture.dart';
import 'src/report.dart';
import 'src/suite.dart';

const String _baselineOption = 'baseline';
const String _jsonOption = 'json';
const String _markdownOption = 'markdown';
const String _helpFlag = 'help';

const String _baselineLabel = 'baseline';
const String _candidateLabel = 'candidate';

const int _usageExitCode = 64;
const int _failureExitCode = 1;

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption(
      _baselineOption,
      valueHelp: 'dir',
      help:
          'The packages/skills_lint directory of another checkout to compare against. '
          'Pass this package directory to measure noise.',
    )
    ..addOption(_jsonOption, valueHelp: 'path', help: 'Also write a JSON report to this file.')
    ..addOption(
      _markdownOption,
      valueHelp: 'path',
      help: 'Also write the Markdown report to this file.',
    )
    ..addFlag(_helpFlag, abbr: 'h', negatable: false, help: 'Show usage information.');
  final ArgResults args;
  try {
    args = parser.parse(arguments);
  } on FormatException catch (e) {
    stderr
      ..writeln(e.message)
      ..writeln(parser.usage);
    exitCode = _usageExitCode;
    return;
  }
  if (args.flag(_helpFlag)) {
    stdout
      ..writeln('Usage: dart run benchmark/run_benchmarks.dart [options]')
      ..writeln(parser.usage);
    return;
  }
  final String? baseline = args.option(_baselineOption);
  if (baseline != null && !File(p.join(baseline, 'bin', 'skills_lint.dart')).existsSync()) {
    stderr.writeln('--$_baselineOption must be a skills_lint package directory: $baseline');
    exitCode = _usageExitCode;
    return;
  }
  final Directory work = Directory.systemTemp.createTempSync('skills_lint_bench_');
  try {
    await _run(
      work.path,
      baseline: baseline,
      jsonPath: args.option(_jsonOption),
      markdownPath: args.option(_markdownOption),
    );
  } on BenchmarkException catch (e) {
    stderr.writeln(e.message);
    exitCode = _failureExitCode;
  } finally {
    work.deleteSync(recursive: true);
  }
}

Future<void> _run(String work, {String? baseline, String? jsonPath, String? markdownPath}) async {
  final String candidateDir = p.dirname(p.dirname(p.fromUri(Platform.script)));
  final List<Target> targets = [
    if (baseline != null) await _build(_baselineLabel, baseline, work),
    await _build(_candidateLabel, candidateDir, work),
  ];
  final RssProbe? rssProbe = RssProbe.detect();
  final List<BenchmarkResult> results = [];
  for (final BenchmarkDefinition definition in benchmarks) {
    final String fixtureDir = p.join(work, 'fixtures', definition.name);
    writeFixture(fixtureDir, definition.fixture);
    stderr.writeln(
      'Running ${definition.name}: ${definition.warmup} warmup and '
      '${definition.iterations} timed runs per build.',
    );
    results.add(
      await runBenchmark(
        definition,
        targets,
        workingDirectory: fixtureDir,
        scratchDirectory: work,
        rssProbe: rssProbe,
      ),
    );
  }

  final List<Comparison> comparisons = baseline == null
      ? const []
      : compare(results, baseline: _baselineLabel, candidate: _candidateLabel);
  final Map<String, String> environment = {
    'OS': Platform.operatingSystemVersion,
    'Dart': Platform.version.split(' ').first,
    'Logical CPUs': '${Platform.numberOfProcessors}',
    'Peak RSS': rssProbe == null
        ? 'not measured on this platform'
        : 'measured with ${RssProbe.timePath}',
  };
  final String markdown = markdownReport(
    results,
    labels: [for (final t in targets) t.label],
    comparisons: comparisons,
    environment: environment,
  );
  stdout.write(markdown);
  if (markdownPath != null) {
    File(markdownPath).writeAsStringSync(markdown);
  }
  if (jsonPath != null) {
    final Map<String, Object?> json = jsonReport(
      results,
      comparisons: comparisons,
      environment: environment,
    );
    File(jsonPath).writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(json)}\n');
  }
  if (Platform.environment['GITHUB_ACTIONS'] == 'true') {
    regressionAnnotations(comparisons).forEach(stdout.writeln);
  }
}

/// Compiles the CLI in [packageDir] to a native executable under [work].
Future<Target> _build(String label, String packageDir, String work) async {
  stderr.writeln('Compiling $label from $packageDir.');
  final String outDir = p.join(work, 'build', label);
  Directory(outDir).createSync(recursive: true);
  final String exe = p.join(outDir, Platform.isWindows ? 'skills_lint.exe' : 'skills_lint');
  await _dart([
    'compile',
    'exe',
    '--verbosity=error',
    'bin/skills_lint.dart',
    '-o',
    exe,
  ], packageDir);
  return Target(label: label, command: [exe]);
}

Future<void> _dart(List<String> arguments, String workingDirectory) async {
  final ProcessResult result = await Process.run(
    Platform.resolvedExecutable,
    arguments,
    workingDirectory: workingDirectory,
  );
  if (result.exitCode != 0) {
    throw BenchmarkException(
      '`dart ${arguments.join(' ')}` failed in $workingDirectory:\n${result.stdout}\n${result.stderr}',
    );
  }
}
