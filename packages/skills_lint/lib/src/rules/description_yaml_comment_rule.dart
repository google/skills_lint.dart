// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:yaml/yaml.dart';
import '../cutoff_excerpt.dart';
import '../models/analysis_severity.dart';
import '../models/skill_context.dart';
import '../models/skill_rule.dart';
import '../models/source_region.dart';
import '../models/validation_error.dart';
import 'valid_yaml_metadata_rule.dart';

/// Enforces that a YAML comment does not cut the description field short.
///
/// In an unquoted (plain) YAML scalar, whitespace followed by `#` starts a
/// comment, so `description: Use when asked "fix #123"` parses as
/// `Use when asked "fix` and an agent never sees the rest. `owner/repo#123`
/// and `C#` have no whitespace before the `#`, so they pass. Quoted and block
/// scalars pass, because a `#` inside them is text.
class DescriptionYamlCommentRule extends SkillRule {
  DescriptionYamlCommentRule({this.severity = defaultSeverity});

  static const String ruleName = 'description-yaml-comment';
  static const AnalysisSeverity defaultSeverity = AnalysisSeverity.disabled;

  @override
  String get name => ruleName;

  @override
  final AnalysisSeverity severity;

  static const _skillFileName = 'SKILL.md';

  /// Whitespace followed by `#` at the start of the text that follows the
  /// parsed scalar on its last line.
  static final RegExp _commentStart = RegExp(r'^[ \t]+#');

  @override
  Future<List<ValidationError>> validate(SkillContext context) async {
    final YamlNode? node = context.parsedYaml?.nodes[ValidYamlMetadataRule.keyDescription];
    if (node is! YamlScalar || node.style != ScalarStyle.PLAIN) {
      return const [];
    }
    final SourceRegion? scalar = context.yamlNodeToRegion(node);
    if (scalar case SourceRegion(endLine: final int line, endColumn: final int scalarEnd)) {
      final String lastLine = const LineSplitter().convert(context.rawContent)[line - 1];
      final String afterScalar = lastLine.substring(scalarEnd - 1);
      final RegExpMatch? comment = _commentStart.firstMatch(afterScalar);
      if (comment != null) {
        return [
          _buildError(
            description: node.value.toString(),
            afterScalar: afterScalar,
            line: line,
            column: scalarEnd + comment.end - 1,
          ),
        ];
      }
    }
    return const [];
  }

  /// The error for a [description] whose source line continues with
  /// [afterScalar], the whitespace and comment that YAML drops, at
  /// 1-based [line] and [column] of the `#`.
  ValidationError _buildError({
    required String description,
    required String afterScalar,
    required int line,
    required int column,
  }) {
    final String dropped = afterScalar.substring(afterScalar.indexOf('#')).trimRight();
    final String excerpt = buildCutoffExcerpt(description + afterScalar, description.length);
    return ValidationError(
      ruleId: name,
      severity: severity,
      file: _skillFileName,
      subject: dropped,
      message: _buildDiagnostic(line: line, column: column, excerpt: excerpt),
      markdownMessage: _buildMarkdownDiagnostic(line: line, column: column, excerpt: excerpt),
      region: SourceRegion(
        startLine: line,
        startColumn: column,
        endLine: line,
        endColumn: column + dropped.length,
      ),
    );
  }

  static String _buildDiagnostic({
    required int line,
    required int column,
    required String excerpt,
  }) {
    return 'Description field is cut short by a YAML comment. In an unquoted value, '
        '" #" starts a comment, so the description ends at |HERE| '
        '(line $line, column $column). '
        'Quote the value (description: "...") or use a block scalar (description: >-). '
        'Cutoff: $excerpt';
  }

  static String _buildMarkdownDiagnostic({
    required int line,
    required int column,
    required String excerpt,
  }) {
    final String boldExcerpt = excerpt.replaceAll('|HERE|', '**|HERE|**');
    return '**Frontmatter `description` is cut short by a YAML comment.**\n\n'
        'In an unquoted value, ` #` starts a comment, so the description ends at '
        '**|HERE|** (line $line, column $column).\n\n'
        '**Cutoff excerpt:**\n'
        '> $boldExcerpt\n\n'
        '**How to fix:**\n'
        '- Quote the value (`description: "..."`), or write it as a block scalar '
        '(`description: >-`).';
  }
}
