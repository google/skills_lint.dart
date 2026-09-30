// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Times each skills_lint rule on its own and prints a Markdown report.
///
/// Run it from the `packages/skills_lint` directory. See `README.md` in this
/// directory for usage and for how to read the report.
library;

import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;
import 'package:skills_lint/skills_lint.dart';

import 'src/fixture.dart';
import 'src/timings.dart';

const String _repoRootOption = 'repo-root';
const String _jsonOption = 'json';
const String _baselineJsonOption = 'baseline-json';
const String _markdownOption = 'markdown';
const String _helpFlag = 'help';

const int _usageExitCode = 64;

/// Size of the generated corpus, the same as the macro benchmark's.
const int _fixtureSkillCount = 1000;

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption(
      _repoRootOption,
      valueHelp: 'dir',
      help:
          'Repository root that holds the real corpus. '
          'Defaults to two levels above the working directory.',
    )
    ..addOption(
      _jsonOption,
      valueHelp: 'path',
      help: 'Also write the timings as JSON to this file.',
    )
    ..addOption(
      _baselineJsonOption,
      valueHelp: 'path',
      help: 'JSON timings of another build (from --$_jsonOption) to compare against.',
    )
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
      ..writeln('Usage: dart run benchmark/rule_timings.dart [options]')
      ..writeln(parser.usage);
    return;
  }

  final String repoRoot =
      args.option(_repoRootOption) ?? p.normalize(p.join(Directory.current.path, '..', '..'));
  final String? baselinePath = args.option(_baselineJsonOption);
  final List<CorpusTimings>? baseline = baselinePath == null ? null : _readTimings(baselinePath);

  final validator = Validator(ruleConfigs: timedRuleConfigs());
  final Directory work = Directory.systemTemp.createTempSync('skills_lint_rule_timings_');
  final List<CorpusTimings> timings;
  try {
    writeFixture(work.path, const FixtureSpec(skillCount: _fixtureSkillCount));
    final Map<String, List<Directory>> corpora = {
      'fixture': findSkillDirectories([p.join(work.path, skillsDirectoryName)]),
      'real': findSkillDirectories([for (final root in realCorpusRoots) p.join(repoRoot, root)]),
    };
    timings = [
      for (final MapEntry(key: name, value: dirs) in corpora.entries)
        if (dirs.isNotEmpty) await _time(name, dirs, validator),
    ];
  } finally {
    work.deleteSync(recursive: true);
  }

  final String markdown = timingsMarkdown(
    timings,
    baseline: baseline,
    defaultRules: {for (final rule in Validator().rules) rule.name},
  );
  stdout.write(markdown);
  final String? markdownPath = args.option(_markdownOption);
  if (markdownPath != null) {
    File(markdownPath).writeAsStringSync(markdown);
  }
  final String? jsonPath = args.option(_jsonOption);
  if (jsonPath != null) {
    final Map<String, Object?> json = {
      TimingJsonKeys.corpora: [for (final t in timings) t.toJson()],
    };
    File(jsonPath).writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(json)}\n');
  }
}

Future<CorpusTimings> _time(String name, List<Directory> dirs, Validator validator) {
  stderr.writeln(
    'Timing ${validator.rules.length} rules on $name (${dirs.length} skills): '
    '$timingWarmup warmup and $timingRepetitions timed samples per rule.',
  );
  return timeRules(name, dirs, validator);
}

List<CorpusTimings> _readTimings(String path) {
  final json = jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;
  return [
    for (final corpus in json[TimingJsonKeys.corpora]! as List<Object?>)
      CorpusTimings.fromJson(corpus! as Map<String, Object?>),
  ];
}
