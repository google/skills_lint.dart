// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';
import 'package:source_span/source_span.dart';
import 'package:yaml/yaml.dart';

import 'source_region.dart';

/// Context provided to [SkillRule]s during validation.
class SkillContext {
  SkillContext({
    required this.directory,
    required this.rawContent,
    this.parsedYaml,
    this.yamlParsingError,
  }) : _sourceFile = SourceFile.fromString(rawContent);

  /// The required filename for skill documentation.
  static const String skillFileName = 'SKILL.md';

  /// Regex to match the YAML frontmatter in SKILL.md.
  static final RegExp skillStartRegex = RegExp(r'^---\s*\n(.*?)\n---\s*\n', dotAll: true);

  /// Regex to match inline Markdown links (`[text](target)`). The capture
  /// group is the link target. Rules that inspect SKILL.md link targets
  /// import this rather than re-defining the pattern.
  static final RegExp markdownLinkRegex = RegExp(r'\[.*?\]\((.*?)\)');

  final Directory directory;

  /// Guaranteed to be non-null because we only run rules if SKILL.md exists.
  final String rawContent;

  final YamlMap? parsedYaml;

  final String? yamlParsingError;

  final SourceFile _sourceFile;

  /// Converts a 0-based character [offset] in [rawContent] (matching indices
  /// returned by `Match.start`, `String.indexOf`, and `SourceSpan.start.offset`)
  /// into a 1-based line number (where line 1 represents the first line of the document).
  int offsetToLine(int offset) {
    if (rawContent.isEmpty) {
      return 1;
    }
    final int clampedOffset = offset.clamp(0, rawContent.length - 1);
    return _sourceFile.getLine(clampedOffset) + 1;
  }

  /// Resolves the 1-based [SourceRegion] in [rawContent] for a given [YamlNode].
  ///
  /// Calculates the absolute character offsets of [node] by combining the frontmatter
  /// boundary offset with [node.span.start.offset] and [node.span.end.offset],
  /// then converts them to 1-based line and column coordinates.
  /// Returns `null` if [node] is null or if frontmatter is not found in [rawContent].
  SourceRegion? yamlNodeToRegion(YamlNode? node) {
    if (node == null) {
      return null;
    }
    final RegExpMatch? match = skillStartRegex.firstMatch(rawContent);
    if (match == null) {
      return null;
    }
    final String yamlStr = match.group(1)!;
    final int yamlOffset = rawContent.indexOf(yamlStr, match.start);
    final int startLine = offsetToLine(yamlOffset + node.span.start.offset);
    final int startColumn = node.span.start.column + 1;
    final int endLine = offsetToLine(yamlOffset + node.span.end.offset);
    final int endColumn = node.span.end.column + 1;
    return SourceRegion(
      startLine: startLine,
      startColumn: startColumn,
      endLine: endLine,
      endColumn: endColumn,
    );
  }
}
