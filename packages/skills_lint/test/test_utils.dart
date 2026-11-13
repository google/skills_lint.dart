// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

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
import 'package:skills_lint/src/yaml_limits.dart';
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

/// Writes `SKILL.md` in [skillDir] with [frontmatter] between `---` lines and
/// a short body, then validates [skillDir] with the default rules.
///
/// [frontmatter] must end with a newline.
Future<ValidationResult> validateFrontmatter(Directory skillDir, String frontmatter) async {
  await File(p.join(skillDir.path, 'SKILL.md')).writeAsString('---\n$frontmatter---\nBody\n');
  return Validator().validate(skillDir);
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
      contains('Unknown rule "$name"'),
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

/// A flow list nested one level deeper than [YamlLimits.maxDepth] allows
/// under a mapping key.
String tooDeepFlowList() {
  const int levels = YamlLimits.maxDepth + 1;
  return '${'[' * levels}${']' * levels}';
}

/// A frontmatter whose `description` expands to 10^9 values through nine
/// levels of ten aliases each.
String billionLaughs({required bool flowStyle}) {
  const levels = 'abcdefghi';
  final buffer = StringBuffer('name: demo\n');
  for (var i = 0; i < levels.length; i++) {
    final item = i == 0 ? 'x' : '*${levels[i - 1]}';
    final items = List<String>.filled(10, item);
    buffer.writeln(
      flowStyle
          ? '${levels[i]}: &${levels[i]} [${items.join(', ')}]'
          : '${levels[i]}: &${levels[i]}\n${items.map((String it) => '  - $it').join('\n')}',
    );
  }
  buffer.writeln('description: *${levels[levels.length - 1]}');
  return buffer.toString();
}
