// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// @docImport 'package:skills_lint/skills_lint.dart';
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_lint/src/models/analysis_severity.dart';
import 'package:skills_lint/src/models/rule_config.dart';
import 'package:skills_lint/src/models/skill_context.dart';
import 'package:skills_lint/src/models/skill_rule.dart';
import 'package:skills_lint/src/models/validation_error.dart';
import 'package:skills_lint/src/suggestions/did_you_mean.dart';
import 'package:skills_lint/src/validator.dart';
import 'package:tar/tar.dart';
import 'package:test/test.dart';
import 'package:test_process/test_process.dart';
import 'package:yaml/yaml.dart';

/// Asserts that [instance] serializes via [toJson] to [expectedJson] (or matching map),
/// and that deserializing via [fromJson] yields an object whose [toJson] output matches [expectedJson]
/// (and equals [instance] if [expectValueEquality] is true).
void expectJsonRoundTrip<T>({
  required T instance,
  required Map<String, Object?> Function(T) toJson,
  required T Function(Map<String, Object?>) fromJson,
  Map<String, Object?>? expectedJson,
  bool expectValueEquality = false,
}) {
  final Map<String, Object?> actualJson = toJson(instance);
  if (expectedJson != null) {
    expect(actualJson, equals(expectedJson));
  }
  final T restored = fromJson(actualJson);
  expect(toJson(restored), equals(actualJson));
  if (expectValueEquality) {
    expect(restored, equals(instance));
  }
}

/// A [Stdout] that collects what is written to it, for use with
/// [IOOverrides.runZoned]. Any member other than [write] and [writeln]
/// throws.
class CapturedOutput implements Stdout {
  final StringBuffer buffer = StringBuffer();

  @override
  void write(Object? object) => buffer.write(object);

  @override
  void writeln([Object? object = '']) => buffer.writeln(object);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Generates a raw YAML frontmatter string delimited by `---`.
String buildFrontmatter({
  String name = 'Skill-Name',
  String description = 'A test skill',
  String? compatibility,
}) {
  final sb = StringBuffer();
  sb.writeln('---');
  sb.writeln('name: $name');
  sb.writeln('description: $description');
  if (compatibility != null) {
    sb.writeln('compatibility: $compatibility');
  }
  sb.writeln('---');
  return sb.toString();
}

/// Creates a temporary directory for testing and automatically cleans it up.
Future<void> withTempDir(FutureOr<void> Function(Directory tempDir) action) async {
  final Directory tempDir = await Directory.systemTemp.createTemp('api_test.');
  try {
    await action(tempDir);
  } finally {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  }
}

/// The compiled skills_lint executable that [startCli] runs, or `null` to run
/// `dart bin/skills_lint.dart`.
String? _compiledCli;

/// Makes [startCli] run [executable], a skills_lint binary built by
/// `dart compile exe`, for the rest of this test isolate.
///
/// Only the tests in `compiled_test/` call this, after they compile the
/// binary. Every other test runs the CLI from source.
void useCompiledCli(String executable) {
  _compiledCli = executable;
}

/// Starts the skills_lint CLI with [arguments] in [workingDirectory].
///
/// Runs `dart bin/skills_lint.dart`, or the binary given to [useCompiledCli].
/// Without a [workingDirectory], the CLI runs in the system temp directory,
/// outside this package, so it reads no `pubspec.yaml` or configuration of
/// this repository.
///
/// A test file that calls this should also run from `compiled_test/`, so the
/// same test covers the compiled binary.
Future<TestProcess> startCli(
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
}) {
  final String? executable = _compiledCli;
  return TestProcess.start(
    executable ?? 'dart',
    [if (executable == null) p.normalize(p.absolute('bin', 'skills_lint.dart')), ...arguments],
    workingDirectory: workingDirectory ?? Directory.systemTemp.path,
    environment: environment,
  );
}

/// Creates a physical skill directory on the filesystem containing a `SKILL.md` file.
Future<Directory> createDummySkill(
  Directory parentDir, {
  required String name,
  required String skillContent,
}) async {
  final Directory skillDir = await Directory(p.join(parentDir.path, name)).create(recursive: true);
  await File(p.join(skillDir.path, 'SKILL.md')).writeAsString(skillContent);
  return skillDir;
}

/// Writes `<parentDir>/<directoryName ?? name>/SKILL.md` with YAML frontmatter
/// and [body], then validates that skill directory.
///
/// Frontmatter fields come from [name], [description], and optional
/// [compatibility]; [ruleConfigs] and [customRules] configure [Validator].
Future<ValidationResult> writeAndValidateSkill(
  Directory parentDir, {
  String name = 'test-skill',
  String? directoryName,
  String description = 'A test skill',
  String? compatibility,
  String body = '',
  Map<String, RuleConfig>? ruleConfigs,
  List<SkillRule>? customRules,
}) async {
  final String frontmatter = buildFrontmatter(
    name: name,
    description: description,
    compatibility: compatibility,
  );
  final Directory skillDir = await createDummySkill(
    parentDir,
    name: directoryName ?? name,
    skillContent: '$frontmatter$body',
  );
  return Validator(ruleConfigs: ruleConfigs, customRules: customRules).validate(skillDir);
}

/// Constructs an in-memory [SkillContext] data object for unit testing [SkillRule]s.
SkillContext createTestSkillContext({
  required Directory directory,
  String? name,
  String description = 'Test',
  String? compatibility,
  String? rawContent,
  YamlMap? parsedYaml,
  String? yamlParsingError,
}) {
  if (yamlParsingError != null) {
    return SkillContext(
      directory: directory,
      rawContent: rawContent ?? '',
      yamlParsingError: yamlParsingError,
    );
  }
  if (rawContent != null && parsedYaml != null) {
    return SkillContext(directory: directory, rawContent: rawContent, parsedYaml: parsedYaml);
  }
  final String effectiveName = name ?? p.basename(directory.path);
  final String effectiveRawContent =
      rawContent ??
      buildFrontmatter(name: effectiveName, description: description, compatibility: compatibility);
  final RegExpMatch? match = SkillContext.skillStartRegex.firstMatch(effectiveRawContent);
  final YamlMap effectiveParsedYaml =
      parsedYaml ?? (match != null ? loadYaml(match.group(1)!) as YamlMap : YamlMap());
  return SkillContext(
    directory: directory,
    rawContent: effectiveRawContent,
    parsedYaml: effectiveParsedYaml,
  );
}

/// A stand-in for `dart pub publish --to-archive` that tests give to
/// `PubArchiveLoader` in place of [Process.run].
///
/// When [exitCode] is 0, [run] writes an archive that holds [archiveFiles].
class FakePub {
  FakePub({this.archiveFiles = const [], this.exitCode = 0, this.stderr = ''});

  static const String _toArchiveOption = '--to-archive=';

  final List<String> archiveFiles;
  final int exitCode;
  final String stderr;

  /// The working directory of each call to [run], in order.
  final List<String> workingDirectories = [];

  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    workingDirectories.add(workingDirectory!);
    if (exitCode == 0) {
      final String archivePath = arguments
          .firstWhere((String argument) => argument.startsWith(_toArchiveOption))
          .substring(_toArchiveOption.length);
      final Stream<TarEntry> entries = Stream.fromIterable([
        for (final String file in archiveFiles)
          TarEntry.data(TarHeader(name: file, mode: 420), utf8.encode(file)),
      ]);
      await entries
          .transform(tarWriter)
          .transform(gzip.encoder)
          .pipe(File(archivePath).openWrite());
    }
    return ProcessResult(0, exitCode, '', stderr);
  }
}

/// A custom rule that finds nothing, for checking how its name is handled.
class QuietRule extends SkillRule {
  QuietRule({this.name = 'my-custom-rule'});

  @override
  final String name;

  @override
  AnalysisSeverity get severity => AnalysisSeverity.disabled;

  @override
  Future<List<ValidationError>> validate(SkillContext context) async => const [];
}

/// Matches a message that reports [name] as unknown, in the section labeled
/// [section], and suggesting [suggestions].
///
/// Checks the parts that matter rather than the exact wording, so a change in
/// punctuation does not break it.
Matcher reportsUnknownRule(String name, {String? section, List<String> suggestions = const []}) =>
    allOf([
      contains('unknown rule "$name"'),
      if (section != null) contains(section),
      if (suggestions.isNotEmpty) contains(didYouMean(suggestions)),
      if (suggestions.isEmpty) contains('newer skills_lint'),
    ]);

/// Matches a [ValidationResult] that is valid and has neither [ValidationResult.errors]
/// nor [ValidationResult.warnings].
// [ValidationResult.isValid] ignores warnings until
// https://github.com/google/skills_lint.dart/issues/140 removes warning severity.
final Matcher hasNoErrorsOrWarnings = isA<ValidationResult>()
    .having((ValidationResult r) => r.isValid, 'isValid', isTrue)
    .having((ValidationResult r) => r.errors, 'errors', isEmpty)
    .having((ValidationResult r) => r.warnings, 'warnings', isEmpty);

/// How severe a configuration problem is in CLI output.
// TODO(reidbaker-agent): Remove `warning` with the warning severity level.
// https://github.com/google/skills_lint.dart/issues/140
enum ConfigProblemLevel { error, warning }

/// A located configuration problem parsed from CLI stderr output.
///
/// Subprocess CLI tests only observe rendered text, not in-process
/// [Configuration] objects, so [configProblemsIn] parses each indented
/// `<file>:<line>:<column>` line (separated from `<message>` by two or more
/// spaces) into this record so matchers check structured fields instead of
/// ad-hoc regular expressions.
typedef ReportedConfigProblem = ({
  ConfigProblemLevel level,
  String file,
  int line,
  int column,
  String message,
});

/// Parses a `<file>:<line>:<column>` string, or returns `null` if [location]
/// does not end with `:<line>:<column>`.
({String file, int line, int column})? parseConfigLocationText(String location) {
  final int columnStart = location.lastIndexOf(':');
  final int lineStart = columnStart <= 0 ? -1 : location.lastIndexOf(':', columnStart - 1);
  if (lineStart <= 0) {
    return null;
  }
  final int? lineNumber = int.tryParse(location.substring(lineStart + 1, columnStart));
  final int? column = int.tryParse(location.substring(columnStart + 1));
  if (lineNumber == null || column == null) {
    return null;
  }
  return (file: location.substring(0, lineStart), line: lineNumber, column: column);
}

/// The located configuration problems that [output] reports, in order.
///
/// The CLI prints a header that counts the configuration errors or warnings,
/// then one indented line per problem with `<file>:<line>:<column>`, two or
/// more spaces for column alignment, and `<message>`. The header gives the
/// level. Lines without a location are left out.
List<ReportedConfigProblem> configProblemsIn(String output) {
  final problems = <ReportedConfigProblem>[];
  ConfigProblemLevel? level;
  for (final String line in const LineSplitter().convert(output)) {
    if (line.trim().isEmpty) {
      continue;
    }
    if (!line.startsWith('  ')) {
      level = _headerLevel(line);
      continue;
    }
    if (level != null) {
      if (_parseConfigProblem(line.trim(), level) case final ReportedConfigProblem problem) {
        problems.add(problem);
      }
    }
  }
  return problems;
}

ConfigProblemLevel? _headerLevel(String line) {
  if (!line.endsWith(':')) {
    return null;
  }
  for (final ConfigProblemLevel level in ConfigProblemLevel.values) {
    if (line.contains(' configuration ${level.name}')) {
      return level;
    }
  }
  return null;
}

ReportedConfigProblem? _parseConfigProblem(String line, ConfigProblemLevel level) {
  // At least two spaces separate the location from the aligned message.
  final int locationEnd = line.indexOf('  ');
  if (locationEnd < 0) {
    return null;
  }
  final ({String file, int line, int column})? parsed = parseConfigLocationText(
    line.substring(0, locationEnd),
  );
  if (parsed == null) {
    return null;
  }
  return (
    level: level,
    file: parsed.file,
    line: parsed.line,
    column: parsed.column,
    message: line.substring(locationEnd).trim(),
  );
}

/// Matches CLI output that reports exactly [message] as a configuration
/// problem of [level], located at a `<file>:<line>:<column>` in the
/// configuration file.
Matcher reportsConfigProblem(
  String message, {
  ConfigProblemLevel level = ConfigProblemLevel.error,
}) => isA<String>().having(
  (String output) => [
    for (final ReportedConfigProblem problem in configProblemsIn(output))
      if (problem.level == level) problem.message,
  ],
  'configuration ${level.name} messages',
  contains(message),
);
