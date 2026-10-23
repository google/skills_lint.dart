// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// @docImport 'skill_rule.dart';
library;

import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:source_span/source_span.dart';
import 'package:yaml/yaml.dart';

import 'pub_archive.dart';
import 'source_region.dart';

/// Context provided to [SkillRule]s during validation.
class SkillContext {
  /// Creates the context for the skill in [directory] whose `SKILL.md` holds
  /// [rawContent].
  ///
  /// Pass [activeDirectoryName] only to validate the skill as if [directory]
  /// had that name. It defaults to the name of [directory].
  SkillContext({
    required this.directory,
    required this.rawContent,
    this.parsedYaml,
    this.yamlParsingError,
    String? activeDirectoryName,
    this.pubArchive,
  }) : activeDirectoryName = activeDirectoryName ?? p.basename(directory.path),
       _sourceFile = SourceFile.fromString(rawContent);

  /// The required filename for skill documentation.
  static const String skillFileName = 'SKILL.md';

  /// Regex to match the YAML frontmatter in SKILL.md.
  static final RegExp skillStartRegex = RegExp(
    r'^---\s*\r?\n(.*?)\r?\n---\s*(?:\r?\n|$)',
    dotAll: true,
  );

  /// Regex to match inline Markdown links (`[text](target)`). The capture
  /// group is the link target. Rules that inspect SKILL.md link targets
  /// import this rather than re-defining the pattern.
  static final RegExp markdownLinkRegex = RegExp(r'\[.*?\]\((.*?)\)');

  final Directory directory;

  /// The name the skill directory has, or will have once a planned rename
  /// happens.
  ///
  /// It is the base name of [directory], unless the skill is validated as if
  /// renamed. Rules that compare against the directory name read this, so
  /// that a planned rename counts before it happens on disk.
  final String activeDirectoryName;

  /// Guaranteed to be non-null because we only run rules if SKILL.md exists.
  final String rawContent;

  final YamlMap? parsedYaml;

  final String? yamlParsingError;

  /// The files pub would publish for the package that holds this skill.
  ///
  /// The validation session sets this only when a rule that needs it, such as
  /// `pub-archive-includes-skill`, is enabled for the skill. Otherwise it is
  /// `null`.
  final PubArchive? pubArchive;

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
  /// boundary offset with the start and end offsets of [node]'s [YamlNode.span],
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
