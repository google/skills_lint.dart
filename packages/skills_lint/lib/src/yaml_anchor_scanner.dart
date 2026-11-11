// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:source_span/source_span.dart';

/// An anchor (`&name`) or alias (`*name`) found in YAML text, with its
/// [SourceSpan] in the scanned string.
typedef YamlAnchorToken = ({String token, SourceSpan span});

enum _FlowKind { sequence, mapping }

/// Finds YAML anchors, aliases, and complex mapping keys in YAML text without
/// parsing it.
///
/// `package:yaml` has no public token API, and loading a document that uses
/// an alias or nested collection as a mapping key can take exponential time,
/// so this scanner works on the text. It follows the YAML rules for where a
/// node can start, and skips quoted scalars, block scalars (`|` and `>`),
/// plain scalar text and comments, so `&`, `*`, `?`, `[` and `{` inside text
/// such as `Tom & Jerry`, `*bold*`, or `[link](url)` are not reported.
// TODO(reidbaker-agent): https://github.com/dart-lang/tools/issues/2839
class YamlAnchorScanner {
  YamlAnchorScanner._(this._yaml);

  /// The first anchor (`&name`) or alias (`*name`) in [yaml], or `null` if it
  /// has none.
  ///
  /// The returned `span` is a [SourceSpan] within [yaml], for
  /// callers such as `YamlLimits.loadFrontmatter` to attach to a
  /// `YamlException`.
  static YamlAnchorToken? firstAnchorOrAlias(String yaml) =>
      YamlAnchorScanner._(yaml)._scan(stopAtAnchors: true);

  /// The [SourceSpan] of the first explicit-key indicator (`?`), alias mapping
  /// key (`*name` used as a key) or collection mapping key (`[...]` or `{...}`
  /// used as a key) in [yaml], or `null` if every mapping key is an implicit
  /// scalar.
  ///
  /// `package:yaml` hashes collection mapping keys deeply on every map lookup,
  /// which takes exponential time when mapping keys nest or an alias key
  /// refers to a collection built from aliases. Rejecting these keys before
  /// parsing bounds key hashing without forbidding aliases, flow sequences or
  /// flow mappings used as values.
  static SourceSpan? firstComplexKey(String yaml) =>
      YamlAnchorScanner._(yaml)._scan(stopAtAnchors: false)?.span;

  final String _yaml;

  /// The open quote character of a quoted scalar that runs onto later lines.
  String? _openQuote;

  /// Open flow collections (`[` and `{`), each recording its kind, opening
  /// character offset in [_yaml], and whether a mapping entry is after `:`.
  final List<(_FlowKind kind, int startOffset, bool inValue)> _flowStack = [];

  /// Whether the current position is inside a flow collection.
  bool get _inFlow => _flowStack.isNotEmpty;

  /// Start offset in [_yaml] of the alias or flow collection that just ended,
  /// kept until the next non-closing token so a trailing `:` marks it as a
  /// key.
  int? _keyCandidateOffset;

  /// Whether the current position can start a node.
  bool _atNodeStart = true;

  /// Whether the current position is inside plain scalar text.
  bool _inPlain = false;

  /// Open block collection indentation columns, starting with `-1` at the
  /// document root as `package:yaml` does.
  final List<int> _blockIndents = [-1];

  /// Minimum indentation of continuation lines for an open block plain scalar,
  /// or `null` when none is open.
  int? _plainMinIndent;

  /// Indentation of the block collection that owns an open block scalar.
  int? _blockScalarParentIndent;

  /// Content indentation of an open block scalar, once known.
  int? _blockScalarIndent;

  /// Column where the current candidate block mapping key started on this line.
  int? _keyStartColumn;

  /// Shorthand tag characters (`ns-tag-char` / URI body without flow
  /// delimiters), matching `package:yaml`'s tag scanner.
  static final RegExp _tagChars = RegExp(r"[0-9A-Za-z_\-;/?:@&=+\$.~*'()%]");

  /// A block scalar header with an indentation indicator (`|2`, `|2-`, `|-2`).
  static final RegExp _indentationIndicator = RegExp(r'^[|>](?:[+-]?([1-9])|([1-9])[+-]?)');

  /// Line breaks as `package:yaml` reads them (`\r\n`, `\r`, `\n`).
  static final RegExp _lineBreak = RegExp('\r\n|\r|\n');

  static int _spaceIndent(String line) {
    var i = 0;
    while (i < line.length && line.codeUnitAt(i) == 0x20) {
      i++;
    }
    return i;
  }

  static int _firstNonBlank(String line) {
    var i = 0;
    while (i < line.length) {
      final int unit = line.codeUnitAt(i);
      if (unit != 0x20 && unit != 0x09) {
        break;
      }
      i++;
    }
    return i;
  }

  static bool _isDocMarker(String line) =>
      (line.startsWith('---') || line.startsWith('...')) &&
      (line.length == 3 || line.codeUnitAt(3) == 0x20 || line.codeUnitAt(3) == 0x09);

  YamlAnchorToken? _scan({required bool stopAtAnchors}) {
    var lineStart = 0;
    for (final RegExpMatch lineBreak in _lineBreak.allMatches(_yaml)) {
      final YamlAnchorToken? found = _scanLine(
        lineStart,
        lineBreak.start,
        stopAtAnchors: stopAtAnchors,
      );
      if (found != null) {
        return found;
      }
      lineStart = lineBreak.end;
    }
    return _scanLine(lineStart, _yaml.length, stopAtAnchors: stopAtAnchors);
  }

  YamlAnchorToken? _scanLine(int start, int end, {required bool stopAtAnchors}) {
    // Outside a quoted scalar, `package:yaml` skips a leading BOM on any line.
    if (_openQuote == null && start < end && _yaml.codeUnitAt(start) == 0xFEFF) {
      start++;
    }
    final String line = _yaml.substring(start, end);
    if (_openQuote != null && _isDocMarker(line)) {
      _openQuote = null;
    }
    final int indent = _spaceIndent(line);
    final int firstNonBlank = _firstNonBlank(line);
    final blank = firstNonBlank == line.length;
    if (_skipsBlockScalarLine(line, indent: indent, blank: blank)) {
      return null;
    }
    if (_openQuote == null && !_inFlow) {
      if (_skipsPlainContinuation(
        line,
        indent: indent,
        firstNonBlank: firstNonBlank,
        blank: blank,
      )) {
        return null;
      }
      if (!blank && line[firstNonBlank] != '#') {
        while (_blockIndents.last > indent) {
          _blockIndents.removeLast();
        }
      }
      _atNodeStart = true;
      _inPlain = false;
      _keyStartColumn = null;
      _keyCandidateOffset = null;
    }
    final YamlAnchorToken? found = _scanText(line, start, stopAtAnchors: stopAtAnchors);
    if (_inPlain && !_inFlow && _plainMinIndent == null) {
      _plainMinIndent = _blockIndents.last + 1;
    }
    return found;
  }

  void _rollBlockIndent(int column) {
    if (!_inFlow && column > _blockIndents.last) {
      _blockIndents.add(column);
    }
  }

  void _resetDocument() {
    _blockIndents
      ..clear()
      ..add(-1);
    _plainMinIndent = null;
    _blockScalarParentIndent = null;
    _blockScalarIndent = null;
    _keyStartColumn = null;
    _keyCandidateOffset = null;
  }

  /// Whether the line belongs to an open block scalar and holds only its text.
  bool _skipsBlockScalarLine(String line, {required int indent, required bool blank}) {
    final int? parentIndent = _blockScalarParentIndent;
    if (parentIndent == null) {
      return false;
    }
    if (blank) {
      return true;
    }
    if (indent == 0 && _isDocMarker(line)) {
      _blockScalarParentIndent = null;
      _blockScalarIndent = null;
      return false;
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
  bool _skipsPlainContinuation(
    String line, {
    required int indent,
    required int firstNonBlank,
    required bool blank,
  }) {
    final int? minIndent = _plainMinIndent;
    if (minIndent == null) {
      return false;
    }
    if (blank) {
      return true;
    }
    if (indent == 0 && _isDocMarker(line)) {
      _plainMinIndent = null;
      return false;
    }
    if (indent >= minIndent && line[firstNonBlank] != '#') {
      return _continuesPlainLine(line, firstNonBlank);
    }
    _plainMinIndent = null;
    return false;
  }

  bool _continuesPlainLine(String line, int start) {
    for (var i = start; i < line.length; i++) {
      final String char = line[i];
      if (char == '#' && (i == 0 || line[i - 1] == ' ' || line[i - 1] == '\t')) {
        return true;
      }
      if (char == ':' && _isIndicator(line, i)) {
        _plainMinIndent = null;
        return false;
      }
    }
    return true;
  }

  YamlAnchorToken? _scanText(String line, int lineOffset, {required bool stopAtAnchors}) {
    int? i = _consumeLinePrefix(line);
    if (i == null) {
      return null;
    }
    while (i! < line.length) {
      final String char = line[i];
      if (_openQuote != null) {
        i = _skipQuoted(line, i);
        continue;
      }
      if (char == ' ' || char == '\t') {
        i++;
        continue;
      }
      if (_startsComment(line, i)) {
        return null;
      }
      if (_atNodeStart) {
        final YamlAnchorToken? hit = _checkNodeStartHit(
          line,
          i,
          lineOffset,
          stopAtAnchors: stopAtAnchors,
        );
        if (hit != null) {
          return hit;
        }
        i = _startNode(line, i, lineOffset);
        if (i == null) {
          return null;
        }
        continue;
      }
      final YamlAnchorToken? keyHit = _checkKeyCandidateColon(
        line,
        i,
        stopAtAnchors: stopAtAnchors,
      );
      if (keyHit != null) {
        return keyHit;
      }
      i = _continueScalar(line, i);
    }
    return null;
  }

  /// Handles column-0 directives (`%`) and document markers (`---` / `...`),
  /// returning the index to scan from or `null` when the directive skips the line.
  int? _consumeLinePrefix(String line) {
    if (_openQuote != null || _inFlow || line.isEmpty) {
      return 0;
    }
    if (line[0] == '%') {
      return null;
    }
    if (_isDocMarker(line)) {
      _resetDocument();
      _atNodeStart = true;
      return 3;
    }
    return 0;
  }

  bool _startsComment(String line, int i) =>
      line[i] == '#' && (!_inPlain || i == 0 || line[i - 1] == ' ' || line[i - 1] == '\t');

  YamlAnchorToken? _checkNodeStartHit(
    String line,
    int i,
    int lineOffset, {
    required bool stopAtAnchors,
  }) {
    final String char = line[i];
    if (stopAtAnchors && (char == '&' || char == '*')) {
      final String token = _tokenAt(line, i);
      final int offset = lineOffset + i;
      return (token: token, span: _spanAt(offset, token.length));
    }
    if (!stopAtAnchors) {
      if (char == '?' && _isIndicator(line, i)) {
        return (token: '?', span: _spanAt(lineOffset + i, 1));
      }
      if ((char == '[' || char == '{') &&
          _inFlow &&
          _flowStack.last.$1 == _FlowKind.mapping &&
          !_flowStack.last.$3) {
        return (token: char, span: _spanAt(lineOffset + i, 1));
      }
    }
    return null;
  }

  YamlAnchorToken? _checkKeyCandidateColon(String line, int i, {required bool stopAtAnchors}) {
    final int? candidate = _keyCandidateOffset;
    if (!stopAtAnchors &&
        candidate != null &&
        line[i] == ':' &&
        (_isIndicator(line, i) || _inFlow && !_inPlain)) {
      return (token: _yaml[candidate], span: _spanAt(candidate, 1));
    }
    return null;
  }

  SourceSpan _spanAt(int offset, int length) =>
      SourceFile.fromString(_yaml).span(offset, offset + length);

  /// Handles the character at [i] where a node can start, and returns the
  /// index to continue from, or `null` when the rest of the line is skipped.
  int? _startNode(String line, int i, int lineOffset) {
    final int? afterProperty = _skipNodeProperty(line, i, lineOffset);
    if (afterProperty != null) {
      return afterProperty;
    }
    final String char = line[i];
    if (char == "'" || char == '"') {
      _markBlockKeyStart(i);
      _openQuote = char;
      _atNodeStart = false;
      _keyCandidateOffset = null;
      return i + 1;
    }
    if (_takesNodeIndicator(line, i)) {
      _keyCandidateOffset = null;
      return i + 1;
    }
    if (_startsFlowToken(char, i, lineOffset)) {
      return i + 1;
    }
    if (!_inFlow && (char == '|' || char == '>')) {
      _startBlockScalar(line, i);
      return null;
    }
    _markBlockKeyStart(i);
    _atNodeStart = false;
    _inPlain = true;
    _keyCandidateOffset = null;
    return i + 1;
  }

  /// Skips a tag (`!`) or anchor/alias (`&`/`*`) at [i], or returns `null`.
  int? _skipNodeProperty(String line, int i, int lineOffset) {
    final String char = line[i];
    if (char == '!') {
      _markBlockKeyStart(i);
      return _endOfTag(line, i);
    }
    if (char == '&' || char == '*') {
      _markBlockKeyStart(i);
      if (char == '*') {
        _atNodeStart = false;
        _keyCandidateOffset = lineOffset + i;
      }
      return _endOfToken(line, i);
    }
    return null;
  }

  void _markBlockKeyStart(int column) {
    if (!_inFlow) {
      _keyStartColumn ??= column;
    }
  }

  /// Whether the character at [i] is a `-`, `?` or `:` indicator, after which
  /// a node starts.
  bool _takesNodeIndicator(String line, int i) {
    final String char = line[i];
    if (!(char == '-' && !_inFlow || char == '?' || char == ':') || !_isIndicator(line, i)) {
      return false;
    }
    if (!_inFlow) {
      final int column = char == ':' && _keyStartColumn != null ? _keyStartColumn! : i;
      _rollBlockIndent(column);
      _keyStartColumn = null;
    } else if (char == ':') {
      _setFlowMappingInValue(true);
    }
    return true;
  }

  /// Handles a flow collection bracket or comma at node start.
  bool _startsFlowToken(String char, int i, int lineOffset) {
    if (char == '[' || char == '{') {
      if (!_inFlow) {
        _keyStartColumn ??= i;
      }
      _flowStack.add((char == '[' ? _FlowKind.sequence : _FlowKind.mapping, lineOffset + i, false));
      _keyCandidateOffset = null;
      return true;
    }
    if (!_inFlow) {
      return false;
    }
    if (char == ']' || char == '}') {
      final (_FlowKind _, int startOffset, bool _) = _flowStack.removeLast();
      _keyCandidateOffset = startOffset;
      _atNodeStart = false;
      return true;
    }
    if (char == ',') {
      _setFlowMappingInValue(false);
      _keyCandidateOffset = null;
      return true;
    }
    return false;
  }

  void _setFlowMappingInValue(bool inValue) {
    if (_inFlow && _flowStack.last.$1 == _FlowKind.mapping) {
      final (_FlowKind kind, int startOffset, bool _) = _flowStack.removeLast();
      _flowStack.add((kind, startOffset, inValue));
    }
  }

  /// Opens the block scalar whose header starts at [i].
  void _startBlockScalar(String line, int i) {
    final int parentIndent = _blockIndents.last;
    _blockScalarParentIndent = parentIndent;
    final RegExpMatch? indicator = _indentationIndicator.firstMatch(line.substring(i));
    if (indicator != null) {
      final int increment = int.parse((indicator.group(1) ?? indicator.group(2))!);
      _blockScalarIndent = parentIndent >= 0 ? parentIndent + increment : increment;
    }
  }

  /// Handles the character at [i] after a scalar has started, and returns the
  /// index to continue from.
  int _continueScalar(String line, int i) {
    final String char = line[i];
    if (char == ':' && (_isIndicator(line, i) || _inFlow && !_inPlain)) {
      _advancePastMappingKey(i);
    } else if (_inFlow && char == ',') {
      _setFlowMappingInValue(false);
      _keyCandidateOffset = null;
      _inPlain = false;
      _atNodeStart = true;
    } else if (_inFlow && (char == ']' || char == '}')) {
      final (_FlowKind _, int startOffset, bool _) = _flowStack.removeLast();
      _keyCandidateOffset = startOffset;
      _inPlain = false;
    } else if (!_inFlow && !_inPlain && (char == '[' || char == '{')) {
      _flowStack.add((char == '[' ? _FlowKind.sequence : _FlowKind.mapping, 0, false));
      _keyCandidateOffset = null;
      _atNodeStart = true;
    } else if (char != ']' && char != '}' && !_inPlain) {
      _keyCandidateOffset = null;
    }
    return i + 1;
  }

  void _advancePastMappingKey(int colonColumn) {
    if (!_inFlow) {
      _rollBlockIndent(_keyStartColumn ?? colonColumn);
      _keyStartColumn = null;
    } else {
      _setFlowMappingInValue(true);
    }
    _keyCandidateOffset = null;
    _inPlain = false;
    _atNodeStart = true;
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
    return next == ' ' || next == '\t' || (_inFlow && ',[]{}'.contains(next));
  }

  int _endOfTag(String line, int i) {
    if (i + 1 < line.length && line[i + 1] == '<') {
      final int close = line.indexOf('>', i + 2);
      return close == -1 ? line.length : close + 1;
    }
    int j = i + 1;
    while (j < line.length && _tagChars.hasMatch(line[j])) {
      j++;
    }
    if (j < line.length && line[j] == '!') {
      j++;
      while (j < line.length && _tagChars.hasMatch(line[j])) {
        j++;
      }
    }
    return j;
  }

  int _endOfToken(String line, int i) {
    int j = i + 1;
    while (j < line.length && !' \t,[]{}'.contains(line[j])) {
      j++;
    }
    return j;
  }

  String _tokenAt(String line, int i) => line.substring(i, _endOfToken(line, i));
}
