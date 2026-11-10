// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:yaml/yaml.dart';

import '../fixable_rule.dart';
import '../models/analysis_severity.dart';
import '../models/skill_context.dart';
import '../models/skill_rule.dart';
import '../models/source_region.dart';
import '../models/validation_error.dart';

/// Reports unquoted frontmatter values that YAML cuts short at a comment.
///
/// In an unquoted (plain) YAML value, whitespace followed by `#` starts a
/// comment, so `description: Fix "#123" now` reads as `Fix "`. The rule
/// checks every unquoted string value in the frontmatter, at any depth,
/// except the top-level `name`: a valid name has no whitespace or `#`, so
/// the text after the `#` is never part of the name. A comment after a value
/// that YAML reads as a number, boolean or null is taken as deliberate.
///
/// The fix wraps the value and the dropped text in single quotes, so YAML
/// reads the full text. It can't tell a deliberate comment from lost text,
/// so a deliberate comment becomes part of the value.
class FrontmatterTruncatedByCommentRule extends SkillRule implements FixableRule {
  FrontmatterTruncatedByCommentRule({this.severity = defaultSeverity});

  static const String ruleName = 'frontmatter-truncated-by-comment';
  static const AnalysisSeverity defaultSeverity = AnalysisSeverity.disabled;

  @override
  String get name => ruleName;

  @override
  final AnalysisSeverity severity;

  @override
  Future<List<ValidationError>> validate(SkillContext context) async {
    return [
      for (final _Truncation truncation in _findTruncations(context))
        _buildError(truncation, _regionOf(context, truncation)),
    ];
  }

  @override
  Future<String> fix(SkillContext context, {Set<String> ignoredSubjects = const {}}) async {
    final String content = context.rawContent;
    final buffer = StringBuffer();
    var copied = 0;
    for (final _Truncation truncation in _findTruncations(context)) {
      if (ignoredSubjects.contains(truncation.path)) {
        continue;
      }
      // In a single-quoted value only `'` is special, and line breaks fold
      // the same way as in a plain value, so quoting in place keeps the text.
      final String text = content.substring(truncation.valueStart, truncation.droppedEnd);
      buffer
        ..write(content.substring(copied, truncation.valueStart))
        ..write("'${text.replaceAll("'", "''")}'");
      copied = truncation.droppedEnd;
    }
    buffer.write(content.substring(copied));
    return buffer.toString();
  }

  ValidationError _buildError(_Truncation truncation, SourceRegion region) {
    final _Truncation(:String path, :String dropped) = truncation;
    // A blank line in a plain value reads as a line break; keep the message
    // on one line.
    final String parsed = truncation.parsed.replaceAll('\n', r'\n');
    return ValidationError(
      ruleId: name,
      severity: severity,
      file: SkillContext.skillFileName,
      // RULES.md documents this subject format. Changing it is a breaking change.
      subject: path,
      message:
          '"$path" is cut short at "#": YAML reads "$parsed" and drops "$dropped". '
          'Quote the value to keep the full text, or move the comment to its own line.',
      markdownMessage:
          '**`$path` is cut short at `#`.**\n\n'
          'In an unquoted YAML value, whitespace followed by `#` starts a comment, '
          'so YAML reads "$parsed" and drops "$dropped".\n\n'
          '**How to fix:**\n'
          '- Quote the value to keep the full text. `--fix` does this.\n'
          '- If the text after `#` is a comment, move it to its own line.',
      region: region,
    );
  }
}

/// An unquoted frontmatter value that a comment cuts short.
///
/// Offsets are 0-based indices into [SkillContext.rawContent].
typedef _Truncation = ({
  /// The keys from the frontmatter root to the value, joined with `.`.
  String path,

  /// The value as YAML reads it, without the dropped text.
  String parsed,

  /// The text from the `#` to the end of its line, without trailing
  /// whitespace.
  String dropped,

  /// The start of the value, after any anchor or tag.
  int valueStart,

  /// The offset of the `#`.
  int droppedStart,

  /// The end of [dropped], before trailing whitespace and the line break.
  int droppedEnd,
});

/// The truncated values in the frontmatter of [context], in file order.
///
/// Skips a value whose position in [SkillContext.parsedYaml] doesn't match
/// [SkillContext.rawContent].
List<_Truncation> _findTruncations(SkillContext context) {
  final YamlMap? yaml = context.parsedYaml;
  final RegExpMatch? match = SkillContext.skillStartRegex.firstMatch(context.rawContent);
  if (yaml == null || match == null) {
    return const [];
  }
  final finder = _TruncationFinder(
    context.rawContent,
    context.rawContent.indexOf(match[1]!, match.start),
  );
  for (final MapEntry(:Object? key, :YamlNode value) in yaml.nodes.entries) {
    final Object? field = (key! as YamlNode).value;
    if (field != 'name') {
      finder.visit(value, '$field');
    }
  }
  return finder.truncations..sort((a, b) => a.valueStart.compareTo(b.valueStart));
}

final class _TruncationFinder {
  _TruncationFinder(this._content, this._frontmatterOffset);

  final String _content;

  /// Offset in [_content] of the frontmatter that YAML spans count from.
  final int _frontmatterOffset;

  final List<_Truncation> truncations = [];

  /// Start offsets of the values found, so a value that an alias repeats
  /// is reported once.
  final Set<int> _seen = {};

  void visit(YamlNode node, String path) {
    switch (node) {
      case YamlMap():
        for (final MapEntry(:Object? key, :YamlNode value) in node.nodes.entries) {
          visit(value, '$path.${(key! as YamlNode).value}');
        }
      case YamlList():
        for (final YamlNode item in node.nodes) {
          visit(item, path);
        }
      case YamlScalar(style: ScalarStyle.PLAIN, value: final String parsed):
        _visitPlainString(node, path, parsed);
      case _:
        break;
    }
  }

  void _visitPlainString(YamlScalar node, String path, String parsed) {
    final int spanStart = _frontmatterOffset + node.span.start.offset;
    final int valueEnd = _frontmatterOffset + node.span.end.offset;
    if (valueEnd > _content.length ||
        _content.substring(spanStart, valueEnd) != node.span.text ||
        !_seen.add(spanStart)) {
      return;
    }
    final int valueStart = _skipProperties(spanStart, valueEnd);
    if (valueStart == valueEnd || _content[valueStart] == '#') {
      // A comment between the properties and the value; not a case to quote.
      return;
    }
    final int droppedStart = _skipBlanks(valueEnd);
    if (droppedStart == valueEnd ||
        droppedStart == _content.length ||
        _content[droppedStart] != '#') {
      return;
    }
    final int droppedEnd = _trimBlanksBefore(_lineEnd(droppedStart));
    truncations.add((
      path: path,
      parsed: parsed,
      dropped: _content.substring(droppedStart, droppedEnd),
      valueStart: valueStart,
      droppedStart: droppedStart,
      droppedEnd: droppedEnd,
    ));
  }

  /// The offset of the first character after the anchors (`&a`), tags
  /// (`!t`) and whitespace at the start of the scalar span that begins at
  /// [offset]. A plain value can't start with `&` or `!`.
  ///
  /// Stops at [end].
  int _skipProperties(int offset, int end) {
    var i = offset;
    while (i < end && (_content[i] == '&' || _content[i] == '!')) {
      while (i < end && !_isBlank(_content[i]) && !_isLineBreak(_content[i])) {
        i++;
      }
      // The value can start on the next line after its tag or anchor.
      while (i < end && (_isBlank(_content[i]) || _isLineBreak(_content[i]))) {
        i++;
      }
    }
    return i;
  }

  /// The first offset at or after [offset] that is not a space or tab.
  int _skipBlanks(int offset) {
    var i = offset;
    while (i < _content.length && _isBlank(_content[i])) {
      i++;
    }
    return i;
  }

  /// The offset of the line break that ends the line holding [offset], or
  /// the length of the content.
  int _lineEnd(int offset) {
    var i = offset;
    while (i < _content.length && !_isLineBreak(_content[i])) {
      i++;
    }
    return i;
  }

  /// The offset before the spaces and tabs that end at [end].
  ///
  /// A character that is not a space or tab must come before [end].
  int _trimBlanksBefore(int end) {
    var i = end;
    while (_isBlank(_content[i - 1])) {
      i--;
    }
    return i;
  }
}

bool _isBlank(String char) => char == ' ' || char == '\t';

bool _isLineBreak(String char) => char == '\n' || char == '\r';

/// The 1-based region of the dropped text of [truncation].
SourceRegion _regionOf(SkillContext context, _Truncation truncation) {
  final String content = context.rawContent;
  final int line = context.offsetToLine(truncation.droppedStart);
  final int lineStart = content.lastIndexOf(RegExp(r'[\r\n]'), truncation.droppedStart) + 1;
  return SourceRegion(
    startLine: line,
    startColumn: truncation.droppedStart - lineStart + 1,
    endLine: line,
    endColumn: truncation.droppedEnd - lineStart + 1,
  );
}
