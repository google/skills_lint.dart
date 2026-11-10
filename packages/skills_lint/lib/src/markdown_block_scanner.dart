// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

const int _tab = 0x09;
const int _newline = 0x0A;
const int _carriageReturn = 0x0D;
const int _space = 0x20;
const int _greaterThan = 0x3E;
const int _backtick = 0x60;
const int _tilde = 0x7E;

/// First non-whitespace characters that can introduce an ATX heading, thematic
/// break, setext heading underline, list item, or code fence.
final Set<int> _blockMarkerChars = {...'#-=+*_`~0123456789'.codeUnits};

final RegExp _atxHeadingPattern = RegExp(r'^#{1,6}(?:[ \t]|$)');
final RegExp _thematicBreakPattern = RegExp(
  r'^(?:-[ \t]*){3,}$|^(?:\*[ \t]*){3,}$|^(?:_[ \t]*){3,}$',
);
final RegExp _setextUnderlinePattern = RegExp(r'^(?:=+|-+)[ \t]*$');
final RegExp _listMarkerToken = RegExp(r'^(?:[-+*]|\d{1,9}[.)])(?=[ \t]|$)');

/// A contiguous non-code slice of Markdown text (a paragraph or ATX heading).
class MarkdownTextBlock {
  const MarkdownTextBlock({
    required this.start,
    required this.end,
    required this.quoteDepth,
    required this.maxDefinitionIndent,
    required this.allowsDefinitions,
  });

  final int start;
  final int end;
  final int quoteDepth;
  final int maxDefinitionIndent;
  final bool allowsDefinitions;
}

class _OpenFence {
  const _OpenFence({required this.markerChar, required this.minLength, required this.quoteDepth});

  final int markerChar;
  final int minLength;
  final int quoteDepth;
}

typedef _LineContext = ({
  int lineStart,
  int lineEnd,
  int contentEnd,
  int quoteDepth,
  int column,
  int pos,
  int paragraphStartCandidate,
});

/// Splits Markdown into non-code [MarkdownTextBlock]s and records the 0-based
/// starting offset of every line.
class MarkdownBlockScanner {
  MarkdownBlockScanner(this._markdown);

  final String _markdown;
  final List<MarkdownTextBlock> _blocks = [];
  final List<int> _lineStarts = [];

  /// Content-indentation stack of enclosing list items.
  final List<int> _listIndents = [];

  _OpenFence? _openFence;
  bool _afterBlankLine = true;
  int? _paragraphStart;
  int _paragraphQuoteDepth = 0;
  int _paragraphMaxDefIndent = 3;

  (List<MarkdownTextBlock>, List<int>) scan() {
    var lineStart = 0;
    while (lineStart < _markdown.length) {
      _lineStarts.add(lineStart);
      final int newline = _markdown.indexOf('\n', lineStart);
      final int lineEnd = newline == -1 ? _markdown.length : newline + 1;
      _processLine(lineStart, lineEnd);
      lineStart = lineEnd;
    }
    _flushParagraph(_markdown.length);
    return (_blocks, _lineStarts);
  }

  int get _baseIndent => _listIndents.isEmpty ? 0 : _listIndents.last;

  void _processLine(int lineStart, int lineEnd) {
    final int contentEnd = stripLineEnding(_markdown, lineStart, lineEnd);
    if (_consumeOpenFenceLine(lineStart, contentEnd)) {
      return;
    }

    final (int quoteDepth, int unquotedStart) = stripQuoteMarkers(_markdown, lineStart, contentEnd);
    if (_paragraphStart != null && quoteDepth > _paragraphQuoteDepth) {
      _flushParagraph(lineStart);
    }

    final (int indent, int nonSpaceStart) = leadingIndent(_markdown, unquotedStart, contentEnd);
    if (nonSpaceStart == contentEnd) {
      _flushParagraph(lineStart);
      _afterBlankLine = true;
      return;
    }

    if (_afterBlankLine) {
      _popListsDeeperThan(indent);
    }

    final _LineContext? remaining = _peelListMarkers((
      lineStart: lineStart,
      lineEnd: lineEnd,
      contentEnd: contentEnd,
      quoteDepth: quoteDepth,
      column: indent,
      pos: nonSpaceStart,
      paragraphStartCandidate: lineStart,
    ));
    if (remaining == null) {
      return;
    }

    if (_handleBlockStructure(remaining)) {
      return;
    }

    if (_paragraphStart == null) {
      _paragraphStart = remaining.paragraphStartCandidate;
      _paragraphQuoteDepth = remaining.quoteDepth;
      _paragraphMaxDefIndent = _baseIndent + 3;
    }
    _afterBlankLine = false;
  }

  /// Peels one or more list markers (such as `- ` or `- - `) at the front of
  /// [line], updating [_listIndents]. Returns `null` when the list item starts
  /// empty or opens with an indented code block on the marker line.
  _LineContext? _peelListMarkers(_LineContext line) {
    var current = line;
    while (current.pos < current.contentEnd && current.column <= _baseIndent + 3) {
      if (!_blockMarkerChars.contains(_markdown.codeUnitAt(current.pos))) {
        break;
      }
      final String rest = _markdown.substring(current.pos, current.contentEnd);
      if (_thematicBreakPattern.hasMatch(rest)) {
        break;
      }
      final RegExpMatch? match = _listMarkerToken.firstMatch(rest);
      if (match == null) {
        break;
      }

      _flushParagraph(current.lineStart);
      _popListsDeeperThan(current.column);

      final int afterMarker = current.pos + match.end;
      final int markerEndCol = current.column + match.end;
      final (int itemCol, int itemPos) = leadingIndent(
        _markdown,
        afterMarker,
        current.contentEnd,
        startColumn: markerEndCol,
      );
      final int spacesAfterMarker = itemCol - markerEndCol;
      if (itemPos == current.contentEnd || spacesAfterMarker >= 5) {
        // CommonMark §5.2: an empty item or an item opening with 4+ spaces
        // past the required post-marker space indents by `markerEndCol + 1`.
        _listIndents.add(markerEndCol + 1);
        _afterBlankLine = false;
        return null;
      }

      _listIndents.add(itemCol);
      final (int innerQuotes, int afterQuotes) = stripQuoteMarkers(
        _markdown,
        itemPos,
        current.contentEnd,
      );
      if (innerQuotes > 0) {
        final (int postQuoteIndent, int postQuotePos) = leadingIndent(
          _markdown,
          afterQuotes,
          current.contentEnd,
        );
        if (postQuotePos == current.contentEnd) {
          _afterBlankLine = false;
          return null;
        }
        current = (
          lineStart: current.lineStart,
          lineEnd: current.lineEnd,
          contentEnd: current.contentEnd,
          quoteDepth: current.quoteDepth + innerQuotes,
          column: itemCol + postQuoteIndent,
          pos: postQuotePos,
          paragraphStartCandidate: postQuotePos,
        );
      } else {
        current = (
          lineStart: current.lineStart,
          lineEnd: current.lineEnd,
          contentEnd: current.contentEnd,
          quoteDepth: current.quoteDepth,
          column: itemCol,
          pos: itemPos,
          paragraphStartCandidate: itemPos,
        );
      }
    }
    return current;
  }

  void _popListsDeeperThan(int column) {
    while (_listIndents.isNotEmpty && column < _listIndents.last) {
      _listIndents.removeLast();
    }
  }

  bool _consumeOpenFenceLine(int lineStart, int contentEnd) {
    final _OpenFence? fence = _openFence;
    if (fence == null) {
      return false;
    }
    final (int quoteDepth, int unquotedStart) = stripQuoteMarkers(
      _markdown,
      lineStart,
      contentEnd,
      maxQuotes: fence.quoteDepth,
    );
    if (quoteDepth < fence.quoteDepth) {
      // The blockquote enclosing the fenced code block ended.
      _openFence = null;
      return false;
    }
    final (int indent, int nonSpaceStart) = leadingIndent(_markdown, unquotedStart, contentEnd);
    if (indent <= _baseIndent + 3 && _isClosingFence(_markdown, nonSpaceStart, contentEnd, fence)) {
      _openFence = null;
    }
    return true;
  }

  bool _handleBlockStructure(_LineContext line) {
    final bool startsMarker = _blockMarkerChars.contains(_markdown.codeUnitAt(line.pos));
    if (line.column <= _baseIndent + 3 && startsMarker) {
      final _OpenFence? opened = _tryOpenFence(
        _markdown,
        line.pos,
        line.contentEnd,
        line.quoteDepth,
      );
      if (opened != null) {
        _flushParagraph(line.lineStart);
        _openFence = opened;
        _afterBlankLine = false;
        return true;
      }
    }

    if (_paragraphStart == null && line.column >= _baseIndent + 4) {
      _afterBlankLine = false;
      return true;
    }

    if (!startsMarker || line.column > _baseIndent + 3) {
      return false;
    }

    final String rest = _markdown.substring(line.pos, line.contentEnd);
    if ((_paragraphStart != null && _setextUnderlinePattern.hasMatch(rest)) ||
        _thematicBreakPattern.hasMatch(rest)) {
      _flushParagraph(line.lineStart);
      _afterBlankLine = false;
      return true;
    }

    if (_atxHeadingPattern.hasMatch(rest)) {
      _flushParagraph(line.lineStart);
      _blocks.add(
        MarkdownTextBlock(
          start: line.pos,
          end: line.lineEnd,
          quoteDepth: line.quoteDepth,
          maxDefinitionIndent: 0,
          allowsDefinitions: false,
        ),
      );
      _afterBlankLine = false;
      return true;
    }

    return false;
  }

  void _flushParagraph(int end) {
    final int? start = _paragraphStart;
    if (start != null && start < end) {
      _blocks.add(
        MarkdownTextBlock(
          start: start,
          end: end,
          quoteDepth: _paragraphQuoteDepth,
          maxDefinitionIndent: _paragraphMaxDefIndent,
          allowsDefinitions: true,
        ),
      );
    }
    _paragraphStart = null;
  }
}

_OpenFence? _tryOpenFence(String text, int start, int end, int quoteDepth) {
  final int first = text.codeUnitAt(start);
  if (first != _backtick && first != _tilde) {
    return null;
  }
  final int fenceEnd = runEnd(text, start, end, first);
  final int length = fenceEnd - start;
  if (length < 3) {
    return null;
  }
  if (first == _backtick && text.substring(fenceEnd, end).contains('`')) {
    return null;
  }
  return _OpenFence(markerChar: first, minLength: length, quoteDepth: quoteDepth);
}

bool _isClosingFence(String text, int start, int end, _OpenFence fence) {
  if (start >= end || text.codeUnitAt(start) != fence.markerChar) {
    return false;
  }
  final int fenceEnd = runEnd(text, start, end, fence.markerChar);
  if (fenceEnd - start < fence.minLength) {
    return false;
  }
  return skipHorizontalSpace(text, fenceEnd, end) == end;
}

/// Column position after leading spaces and tabs in [text] from [start] to
/// [end] (advancing from [startColumn] with 4-space tab stops), paired with the
/// index of the first non-whitespace character.
(int, int) leadingIndent(String text, int start, int end, {int startColumn = 0}) {
  var column = startColumn;
  var i = start;
  while (i < end) {
    final int char = text.codeUnitAt(i);
    if (char == _space) {
      column++;
    } else if (char == _tab) {
      column += 4 - (column % 4);
    } else {
      break;
    }
    i++;
  }
  return (column, i);
}

/// Leading CommonMark `>` blockquote marker count in [text] from [start] to
/// [end] (up to [maxQuotes] when given), paired with the offset after those
/// markers.
(int, int) stripQuoteMarkers(String text, int start, int end, {int? maxQuotes}) {
  var depth = 0;
  var pos = start;
  while (maxQuotes == null || depth < maxQuotes) {
    final (int indent, int markerPos) = leadingIndent(text, pos, end);
    if (indent > 3 || markerPos >= end || text.codeUnitAt(markerPos) != _greaterThan) {
      break;
    }
    depth++;
    pos = markerPos + 1;
    if (pos < end) {
      final int next = text.codeUnitAt(pos);
      if (next == _space || next == _tab) {
        pos++;
      }
    }
  }
  return (depth, pos);
}

/// Offset of the end of [text] in `[start, end)` before any trailing `\r\n` or
/// `\n`.
int stripLineEnding(String text, int start, int end) {
  var contentEnd = end;
  if (contentEnd > start && text.codeUnitAt(contentEnd - 1) == _newline) {
    contentEnd--;
  }
  if (contentEnd > start && text.codeUnitAt(contentEnd - 1) == _carriageReturn) {
    contentEnd--;
  }
  return contentEnd;
}

/// Offset in [text] after the contiguous run of [char] starting at [start]
/// within `[start, end)`.
int runEnd(String text, int start, int end, int char) {
  var i = start;
  while (i < end && text.codeUnitAt(i) == char) {
    i++;
  }
  return i;
}

/// Offset in [text] after spaces and tabs starting at [start] within
/// `[start, end)`.
int skipHorizontalSpace(String text, int start, int end) {
  var i = start;
  while (i < end) {
    final int char = text.codeUnitAt(i);
    if (char != _space && char != _tab) {
      break;
    }
    i++;
  }
  return i;
}
