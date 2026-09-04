// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:skills_lint/src/models/skill_context.dart';
import 'package:yaml/yaml.dart';

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
///
/// Use this helper for integration tests, CLI execution, or tests exercising
/// [Validator] file discovery that require actual files on disk.
///
/// For fast, isolated unit tests that validate rules against in-memory models
/// without disk I/O, use [createTestSkillContext] instead.
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
///
/// This helper builds pre-parsed YAML metadata and raw content directly in
/// memory without creating or writing files to the filesystem.
///
/// If [rawContent] or [parsedYaml] are omitted, valid frontmatter is
/// automatically generated using [name] (defaulting to the basename of
/// [directory]), [description], and optional [compatibility].
///
/// For integration tests that require physical directories and files on disk,
/// use [createDummySkill] instead.
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
  final buffer = StringBuffer();
  buffer.writeln('name: $effectiveName');
  buffer.writeln('description: $description');
  if (compatibility != null) {
    buffer.writeln('compatibility: $compatibility');
  }
  final YamlMap effectiveParsedYaml = parsedYaml ?? (loadYaml(buffer.toString()) as YamlMap);
  return SkillContext(
    directory: directory,
    rawContent: effectiveRawContent,
    parsedYaml: effectiveParsedYaml,
  );
}
