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
final RegExp _listMarkerToken = RegExp(r'^(?:[-+*]|(\d{1,9})[.)])(?=[ \t]|$)');

/// A BlockQuote (`>`) or ListItem container on [MarkdownBlockScanner]'s active
/// container stack, ordered from outermost to innermost.
sealed class ContainerMarker {
  const ContainerMarker();
}

/// A CommonMark `>` blockquote container.
final class QuoteContainer extends ContainerMarker {
  const QuoteContainer();
}

/// A CommonMark list item container whose child blocks must be indented by at
/// least [indent] columns relative to its enclosing container.
final class ListItemContainer extends ContainerMarker {
  ListItemContainer(this.indent, {required this.startedEmpty});

  final int indent;

  /// True when the list marker line had no content and no non-blank line has
  /// been seen inside this item yet (CommonMark §5.2: an item can begin with at
  /// most one blank line).
  bool startedEmpty;
}

/// A contiguous non-code slice of Markdown text (a paragraph or ATX heading).
class MarkdownTextBlock {
  const MarkdownTextBlock({
    required this.start,
    required this.end,
    required this.containers,
    required this.allowsDefinitions,
  });

  final int start;
  final int end;

  /// Active outer-to-inner containers enclosing this block, used to peel
  /// prefixes on continuation lines of multi-line `[ref]:` definitions.
  final List<ContainerMarker> containers;

  final bool allowsDefinitions;
}

class _OpenFence {
  const _OpenFence({required this.markerChar, required this.minLength, required this.containers});

  final int markerChar;
  final int minLength;
  final List<ContainerMarker> containers;
}

typedef _LineCursor = ({
  int lineStart,
  int lineEnd,
  int contentEnd,
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
  final List<ContainerMarker> _containers = [];

  _OpenFence? _openFence;
  int? _paragraphStart;
  List<ContainerMarker> _paragraphContainers = const [];

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

  void _processLine(int lineStart, int lineEnd) {
    final int contentEnd = stripLineEnding(_markdown, lineStart, lineEnd);
    if (_consumeOpenFenceLine(lineStart, contentEnd)) {
      return;
    }

    final (int matched, int column, int pos) = matchContainers(
      _markdown,
      lineStart,
      contentEnd,
      _containers,
    );
    final (int nonSpaceCol, int nonSpacePos) = leadingIndent(
      _markdown,
      pos,
      contentEnd,
      startColumn: column,
    );
    final isBlankAfterMatched = nonSpacePos == contentEnd;

    if (isBlankAfterMatched) {
      _flushParagraph(lineStart);
      if (!onlyListContainersRemain(_containers, matched)) {
        _truncateContainers(_firstUnmatchedQuoteIndex(_containers, matched));
      }
      if (_containers.isNotEmpty) {
        if (_containers.last case ListItemContainer(startedEmpty: true)) {
          _containers.removeLast();
        }
      }
      return;
    }

    if (_paragraphStart != null && matched < _containers.length) {
      // Lazy paragraph continuation across unmatched `>` or list-item indents,
      // unless the unmatched line opens a block that can interrupt a paragraph
      // inside the matched prefix.
      _truncateContainers(matched);
      final _LineCursor lazyCursor = (
        lineStart: lineStart,
        lineEnd: lineEnd,
        contentEnd: contentEnd,
        column: nonSpaceCol,
        pos: nonSpacePos,
        paragraphStartCandidate: lineStart,
      );
      if (!_interruptsLazyParagraph(lazyCursor)) {
        _markListItemsNonEmpty();
        return;
      }
    } else {
      _truncateContainers(matched);
    }

    _markListItemsNonEmpty();
    final _LineCursor? remaining = _openNewContainers((
      lineStart: lineStart,
      lineEnd: lineEnd,
      contentEnd: contentEnd,
      column: nonSpaceCol,
      pos: nonSpacePos,
      paragraphStartCandidate: lineStart,
    ));
    if (remaining == null) {
      return;
    }

    if (_handleLeafBlock(remaining)) {
      return;
    }

    if (_paragraphStart == null) {
      _paragraphStart = remaining.paragraphStartCandidate;
      _paragraphContainers = List<ContainerMarker>.unmodifiable(_containers);
    }
  }

  /// Opens any new `>` blockquotes and list-item markers at the front of
  /// [cursor]. Returns `null` when a newly opened container has no remaining
  /// inline text on this line (or opens an indented code block on the marker
  /// line).
  _LineCursor? _openNewContainers(_LineCursor cursor) {
    var current = cursor;
    while (current.pos < current.contentEnd && current.column <= 3) {
      if (_markdown.codeUnitAt(current.pos) == _greaterThan) {
        final _LineCursor? next = _openQuoteContainer(current);
        if (next == null) {
          return null;
        }
        current = next;
        continue;
      }
      final (bool matchedList, _LineCursor? next) = _tryOpenListItem(current);
      if (!matchedList) {
        break;
      }
      if (next == null) {
        return null;
      }
      current = next;
    }
    return current;
  }

  _LineCursor? _openQuoteContainer(_LineCursor current) {
    _flushParagraph(current.lineStart);
    _containers.add(const QuoteContainer());
    final int afterGt = _stepPastQuoteMarker(_markdown, current.pos, current.contentEnd);
    final (int nextCol, int nextPos) = leadingIndent(_markdown, afterGt, current.contentEnd);
    if (nextPos == current.contentEnd) {
      return null;
    }
    return (
      lineStart: current.lineStart,
      lineEnd: current.lineEnd,
      contentEnd: current.contentEnd,
      column: nextCol,
      pos: nextPos,
      paragraphStartCandidate: nextPos,
    );
  }

  (bool, _LineCursor?) _tryOpenListItem(_LineCursor current) {
    if (!_blockMarkerChars.contains(_markdown.codeUnitAt(current.pos))) {
      return (false, null);
    }
    final String rest = _markdown.substring(current.pos, current.contentEnd);
    if (_thematicBreakPattern.hasMatch(rest)) {
      return (false, null);
    }
    final RegExpMatch? match = _listMarkerToken.firstMatch(rest);
    if (match == null) {
      return (false, null);
    }

    final int afterMarker = current.pos + match.end;
    final int markerSpanCols = current.column + match.end;
    final (int postCol, int itemPos) = leadingIndent(
      _markdown,
      afterMarker,
      current.contentEnd,
      startColumn: markerSpanCols,
    );
    final emptyMarkerLine = itemPos == current.contentEnd;
    final String? orderedDigits = match.group(1);
    if (_paragraphStart != null &&
        (emptyMarkerLine || (orderedDigits != null && orderedDigits != '1'))) {
      // CommonMark §5.2: an empty list item or an ordered list item not
      // numbered `1` cannot interrupt an open paragraph.
      return (false, null);
    }

    _flushParagraph(current.lineStart);
    final int spacesAfterMarker = postCol - markerSpanCols;
    if (emptyMarkerLine || spacesAfterMarker >= 5) {
      _containers.add(ListItemContainer(markerSpanCols + 1, startedEmpty: emptyMarkerLine));
      return (true, null);
    }

    _containers.add(ListItemContainer(postCol, startedEmpty: false));
    return (
      true,
      (
        lineStart: current.lineStart,
        lineEnd: current.lineEnd,
        contentEnd: current.contentEnd,
        column: 0,
        pos: itemPos,
        paragraphStartCandidate: itemPos,
      ),
    );
  }

  /// Whether [line] opens a container or leaf block that interrupts a lazy
  /// paragraph continuation (so `_processLine` should flush the paragraph and
  /// re-parse [line] normally).
  bool _interruptsLazyParagraph(_LineCursor line) {
    if (line.column > 3 || line.pos >= line.contentEnd) {
      return false;
    }
    final int char = _markdown.codeUnitAt(line.pos);
    if (char == _greaterThan) {
      return true;
    }
    if (!_blockMarkerChars.contains(char)) {
      return false;
    }
    if (_tryOpenFence(_markdown, line.pos, line.contentEnd, const []) != null) {
      return true;
    }
    final String rest = _markdown.substring(line.pos, line.contentEnd);
    if (_thematicBreakPattern.hasMatch(rest) || _atxHeadingPattern.hasMatch(rest)) {
      return true;
    }
    final RegExpMatch? listMatch = _listMarkerToken.firstMatch(rest);
    if (listMatch == null) {
      return false;
    }
    final String? digits = listMatch.group(1);
    if (digits != null && digits != '1') {
      return false;
    }
    final int afterMarker = skipHorizontalSpace(
      _markdown,
      line.pos + listMatch.end,
      line.contentEnd,
    );
    return afterMarker < line.contentEnd;
  }

  bool _consumeOpenFenceLine(int lineStart, int contentEnd) {
    final _OpenFence? fence = _openFence;
    if (fence == null) {
      return false;
    }
    final (int matched, int column, int pos) = matchContainers(
      _markdown,
      lineStart,
      contentEnd,
      fence.containers,
    );
    final (int nonSpaceCol, int nonSpacePos) = leadingIndent(
      _markdown,
      pos,
      contentEnd,
      startColumn: column,
    );
    if (matched < fence.containers.length) {
      // Blank lines inside a list item keep an unclosed fence open across blank
      // lines, whereas missing a `>` blockquote marker or dedenting a non-blank
      // line closes the enclosing container and ends the fence.
      final bool onlyUnmatchedListsOnBlankLine =
          nonSpacePos == contentEnd && onlyListContainersRemain(fence.containers, matched);
      if (onlyUnmatchedListsOnBlankLine) {
        return true;
      }
      _openFence = null;
      return false;
    }
    if (nonSpaceCol <= 3 && _isClosingFence(_markdown, nonSpacePos, contentEnd, fence)) {
      _openFence = null;
    }
    return true;
  }

  bool _handleLeafBlock(_LineCursor line) {
    final bool startsMarker = _blockMarkerChars.contains(_markdown.codeUnitAt(line.pos));
    if (line.column <= 3 && startsMarker) {
      final _OpenFence? opened = _tryOpenFence(
        _markdown,
        line.pos,
        line.contentEnd,
        List<ContainerMarker>.unmodifiable(_containers),
      );
      if (opened != null) {
        _flushParagraph(line.lineStart);
        _openFence = opened;
        return true;
      }
    }

    if (_paragraphStart == null && line.column >= 4) {
      return true;
    }

    if (!startsMarker || line.column > 3) {
      return false;
    }

    final String rest = _markdown.substring(line.pos, line.contentEnd);
    if ((_paragraphStart != null && _setextUnderlinePattern.hasMatch(rest)) ||
        _thematicBreakPattern.hasMatch(rest)) {
      _flushParagraph(line.lineStart);
      return true;
    }

    if (_atxHeadingPattern.hasMatch(rest)) {
      _flushParagraph(line.lineStart);
      _blocks.add(
        MarkdownTextBlock(
          start: line.pos,
          end: line.lineEnd,
          containers: List<ContainerMarker>.unmodifiable(_containers),
          allowsDefinitions: false,
        ),
      );
      return true;
    }

    return false;
  }

  void _truncateContainers(int keepCount) {
    if (_containers.length > keepCount) {
      _containers.removeRange(keepCount, _containers.length);
    }
  }

  void _markListItemsNonEmpty() {
    for (final ContainerMarker marker in _containers) {
      if (marker case final ListItemContainer item) {
        item.startedEmpty = false;
      }
    }
  }

  void _flushParagraph(int end) {
    final int? start = _paragraphStart;
    if (start != null && start < end) {
      _blocks.add(
        MarkdownTextBlock(
          start: start,
          end: end,
          containers: _paragraphContainers,
          allowsDefinitions: true,
        ),
      );
    }
    _paragraphStart = null;
    _paragraphContainers = const [];
  }
}

int _firstUnmatchedQuoteIndex(List<ContainerMarker> containers, int fromIndex) {
  for (var i = fromIndex; i < containers.length; i++) {
    if (containers[i] is QuoteContainer) {
      return i;
    }
  }
  return containers.length;
}

/// Whether every entry in [containers] starting at [fromIndex] is a
/// [ListItemContainer] (rather than an unmatched [QuoteContainer]).
bool onlyListContainersRemain(List<ContainerMarker> containers, int fromIndex) {
  return _firstUnmatchedQuoteIndex(containers, fromIndex) == containers.length;
}

/// Matches as many outer-to-inner [containers] as [text] satisfies on the line
/// `[lineStart, contentEnd)`, returning `(matchedCount, remainingColumn, pos)`.
///
/// When a tab straddles a list-item indentation boundary (expanding past
/// `item.indent`), the leftover tab spaces carry forward in `remainingColumn`.
(int, int, int) matchContainers(
  String text,
  int lineStart,
  int contentEnd,
  List<ContainerMarker> containers,
) {
  var column = 0;
  var pos = lineStart;
  for (var idx = 0; idx < containers.length; idx++) {
    switch (containers[idx]) {
      case QuoteContainer():
        final (int indent, int markerPos) = leadingIndent(
          text,
          pos,
          contentEnd,
          startColumn: column,
        );
        if (indent > 3 || markerPos >= contentEnd || text.codeUnitAt(markerPos) != _greaterThan) {
          return (idx, column, pos);
        }
        pos = _stepPastQuoteMarker(text, markerPos, contentEnd);
        column = 0;
      case ListItemContainer(:final int indent):
        final (int finalCol, int nextPos) = _consumeColumns(
          text,
          pos,
          contentEnd,
          startColumn: column,
          requiredColumns: indent,
        );
        if (finalCol < indent) {
          return (idx, column, pos);
        }
        column = finalCol - indent;
        pos = nextPos;
    }
  }
  return (containers.length, column, pos);
}

int _stepPastQuoteMarker(String text, int gtPos, int end) {
  final int afterGt = gtPos + 1;
  if (afterGt < end) {
    final int next = text.codeUnitAt(afterGt);
    if (next == _space || next == _tab) {
      return afterGt + 1;
    }
  }
  return afterGt;
}

(int, int) _consumeColumns(
  String text,
  int start,
  int end, {
  required int startColumn,
  required int requiredColumns,
}) {
  var column = startColumn;
  var pos = start;
  while (column < requiredColumns && pos < end) {
    final int char = text.codeUnitAt(pos);
    if (char == _space) {
      column++;
    } else if (char == _tab) {
      column += 4 - (column % 4);
    } else {
      break;
    }
    pos++;
  }
  return (column, pos);
}

_OpenFence? _tryOpenFence(String text, int start, int end, List<ContainerMarker> containers) {
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
  return _OpenFence(markerChar: first, minLength: length, containers: containers);
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
