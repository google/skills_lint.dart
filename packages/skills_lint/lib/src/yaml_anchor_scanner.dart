// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// An anchor (`&name`) or alias (`*name`) that [YamlAnchorScanner] found.
typedef YamlAnchorToken = ({String token, int offset});

/// Finds YAML anchors and aliases in YAML text without parsing it.
///
/// `package:yaml` has no public token API, and loading a document that uses
/// an alias as a mapping key can take exponential time, so this scanner works
/// on the text. It follows the YAML rules for where a node can start, and
/// skips quoted scalars, block scalars (`|` and `>`), plain scalar text and
/// comments, so `&` and `*` inside text such as `Tom & Jerry` or `*bold*` are
/// not reported.
// TODO(reidbaker-agent): https://github.com/dart-lang/tools/issues/2839
class YamlAnchorScanner {
  YamlAnchorScanner._(this._yaml);

  /// Finds the first anchor or alias in [yaml], or `null` if it has none.
  static YamlAnchorToken? firstAnchorOrAlias(String yaml) => YamlAnchorScanner._(yaml)._scan();

  final String _yaml;

  /// The open quote character of a quoted scalar that runs onto later lines.
  String? _openQuote;

  /// Flow collections (`[` and `{`) that are open at the current position.
  int _flowDepth = 0;

  /// Whether the current position can start a node.
  bool _atNodeStart = true;

  /// Whether the current position is inside plain scalar text.
  bool _inPlain = false;

  /// The column of the node that owns a block plain scalar, which continues
  /// onto lines indented past that column.
  int? _plainLineIndent;

  /// The column of the node that owns an open block scalar.
  int? _blockScalarParentIndent;

  /// The indentation of a block scalar's content, once it is known.
  int? _blockScalarIndent;

  /// The column of the block node that the current line position belongs
  /// to: the line's indentation, the last `-` or `?` indicator, or the start
  /// of the last mapping key.
  int _nodeColumn = 0;

  /// The column where the last scalar on the line started.
  int _scalarColumn = 0;

  /// Line breaks as `package:yaml` reads them.
  static final RegExp _lineBreak = RegExp('\r\n|\r|\n');

  YamlAnchorToken? _scan() {
    // A byte order mark is not part of the first line's content.
    var lineStart = _yaml.startsWith('\uFEFF') ? 1 : 0;
    for (final RegExpMatch lineBreak in _lineBreak.allMatches(_yaml, lineStart)) {
      final YamlAnchorToken? found = _scanLine(lineStart, lineBreak.start);
      if (found != null) {
        return found;
      }
      lineStart = lineBreak.end;
    }
    return _scanLine(lineStart, _yaml.length);
  }

  YamlAnchorToken? _scanLine(int start, int end) {
    final String line = _yaml.substring(start, end);
    final int indent = line.length - line.trimLeft().length;
    final bool blank = line.trim().isEmpty;
    if (_skipsBlockScalarLine(indent: indent, blank: blank)) {
      return null;
    }
    if (_openQuote == null && _flowDepth == 0) {
      if (_skipsPlainContinuation(line, indent: indent, blank: blank)) {
        return null;
      }
      _atNodeStart = true;
      _inPlain = false;
    }
    _nodeColumn = indent;
    final YamlAnchorToken? found = _scanText(line, start, indent);
    if (_inPlain && _flowDepth == 0 && _plainLineIndent == null) {
      _plainLineIndent = _nodeColumn;
    }
    return found;
  }

  /// Whether the line belongs to an open block scalar and holds only its text.
  bool _skipsBlockScalarLine({required int indent, required bool blank}) {
    final int? parentIndent = _blockScalarParentIndent;
    if (parentIndent == null) {
      return false;
    }
    if (blank) {
      return true;
    }
    final int contentIndent = _blockScalarIndent ??= indent;
    if (indent > parentIndent && indent >= contentIndent) {
      return true;
    }
    _blockScalarParentIndent = null;
    _blockScalarIndent = null;
    return false;
  }

  /// Whether the line continues a block plain scalar from an earlier line.
  bool _skipsPlainContinuation(String line, {required int indent, required bool blank}) {
    final int? plainIndent = _plainLineIndent;
    if (plainIndent == null) {
      return false;
    }
    if (blank) {
      return true;
    }
    if (indent > plainIndent && !line.trimLeft().startsWith('#')) {
      return true;
    }
    _plainLineIndent = null;
    return false;
  }

  YamlAnchorToken? _scanText(String line, int lineOffset, int indent) {
    var i = 0;
    while (i < line.length) {
      final String char = line[i];
      if (_openQuote != null) {
        i = _skipQuoted(line, i);
        continue;
      }
      final bool afterSpace = i == 0 || line[i - 1] == ' ' || line[i - 1] == '\t';
      if (char == ' ' || char == '\t') {
        i++;
        continue;
      }
      if (char == '#' && afterSpace) {
        return null;
      }
      if (_atNodeStart) {
        if (char == '&' || char == '*') {
          return (token: _tokenAt(line, i), offset: lineOffset + i);
        }
        final int? next = _startNode(line, i);
        if (next == null) {
          return null;
        }
        i = next;
        continue;
      }
      i = _continueScalar(line, i);
    }
    return null;
  }

  /// Handles the character at [i] where a node can start, and returns the
  /// index to continue from, or `null` when the rest of the line is skipped.
  int? _startNode(String line, int i) {
    final String char = line[i];
    final bool flow = _flowDepth > 0;
    if (i == 0 && (line.startsWith('---') || line.startsWith('...')) && _isIndicator(line, 2)) {
      // A document marker, which a node can follow on the same line.
      return 3;
    }
    if (char == '!') {
      return _endOfToken(line, i);
    }
    if (char == "'" || char == '"') {
      _openQuote = char;
      _atNodeStart = false;
      _scalarColumn = i;
      return i + 1;
    }
    if ((char == '-' && !flow || char == '?' || char == ':') && _isIndicator(line, i)) {
      if (!flow && char != ':') {
        _nodeColumn = i;
      }
      return i + 1;
    }
    if (char == '[' || char == '{') {
      _flowDepth++;
      return i + 1;
    }
    if (flow && (char == ']' || char == '}')) {
      _flowDepth--;
      _atNodeStart = false;
      return i + 1;
    }
    if (flow && char == ',') {
      return i + 1;
    }
    if (!flow && (char == '|' || char == '>')) {
      _blockScalarParentIndent = _nodeColumn;
      // An indentation indicator such as `|2` fixes the content indentation
      // relative to the owning node. Without one, the first line sets it.
      final RegExpMatch? indicator = RegExp(r'^[|>][+-]?([1-9])').firstMatch(line.substring(i));
      if (indicator != null) {
        _blockScalarIndent = _nodeColumn + int.parse(indicator.group(1)!);
      }
      return null;
    }
    _atNodeStart = false;
    _inPlain = true;
    _scalarColumn = i;
    return i + 1;
  }

  /// Handles the character at [i] after a scalar has started, and returns the
  /// index to continue from.
  int _continueScalar(String line, int i) {
    final String char = line[i];
    final bool flow = _flowDepth > 0;
    if (char == ':' && (_isIndicator(line, i) || flow && !_inPlain)) {
      if (!flow) {
        _nodeColumn = _scalarColumn;
      }
      _inPlain = false;
      _atNodeStart = true;
    } else if (flow && char == ',') {
      _inPlain = false;
      _atNodeStart = true;
    } else if (flow && (char == ']' || char == '}')) {
      _inPlain = false;
      _flowDepth--;
    }
    return i + 1;
  }

  /// Skips quoted scalar text from [i], and returns the index after the
  /// closing quote, or the line length if the scalar continues.
  int _skipQuoted(String line, int i) {
    final String quote = _openQuote!;
    var j = i;
    while (j < line.length) {
      final String char = line[j];
      if (quote == '"' && char == r'\') {
        j += 2;
        continue;
      }
      if (char == quote) {
        if (quote == "'" && j + 1 < line.length && line[j + 1] == "'") {
          j += 2;
          continue;
        }
        _openQuote = null;
        return j + 1;
      }
      j++;
    }
    return line.length;
  }

  /// Whether the indicator character at [i] is followed by a space, a tab,
  /// the end of the line or, in a flow collection, a flow indicator.
  bool _isIndicator(String line, int i) {
    if (i + 1 >= line.length) {
      return true;
    }
    final String next = line[i + 1];
    return next == ' ' || next == '\t' || (_flowDepth > 0 && ',[]{}'.contains(next));
  }

  int _endOfToken(String line, int i) {
    var j = i;
    while (j < line.length && !' \t,[]{}'.contains(line[j])) {
      j++;
    }
    return j;
  }

  String _tokenAt(String line, int i) => line.substring(i, _endOfToken(line, i));
}
