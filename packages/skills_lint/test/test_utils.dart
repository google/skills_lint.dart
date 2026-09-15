// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_lint/src/models/skill_context.dart';
import 'package:test/test.dart';
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
