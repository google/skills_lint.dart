// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// @docImport 'package:skills_lint/src/models/skill_rule.dart';
library;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_lint/src/models/skill_context.dart';
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
