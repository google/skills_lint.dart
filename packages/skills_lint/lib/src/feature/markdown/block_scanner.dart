// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:meta/meta.dart';
import 'package:source_span/source_span.dart';

import 'char_codes.dart';

/// The blocks of a Markdown document that can hold links.
@immutable
final class MarkdownBlocks {
  const MarkdownBlocks({required this.text, required this.blocks});

  /// The document with spaces in place of everything that cannot hold a link:
  /// the text before the scan starts, code blocks, thematic breaks, and the
  /// `>` and list markers at the start of lines.
  ///
  /// Line endings are kept, so every offset matches the source.
  final String text;

  /// Each paragraph and heading, in document order. A link or a code span
  /// never crosses from one block to the next.
  final List<FileSpan> blocks;
}

/// Splits the Markdown in [file], from offset [start], into the blocks that
/// can hold links.
///
/// Follows the block rules of the CommonMark specification
/// (https://spec.commonmark.org/0.31.2/#blocks-and-inlines): blockquotes and
/// list items nest, a paragraph can continue lazily on a line that drops their
/// markers, and fenced and indented code blocks hold no links. Indentation
/// counts tabs to the next multiple of 4 columns.
///
/// HTML blocks are read as text, so link syntax inside them is scanned.
MarkdownBlocks scanMarkdownBlocks(SourceFile file, {int start = 0}) =>
    _BlockScanner(file, start).scan();

/// A blockquote or list item that holds the lines after it.
sealed class _Container {}

final class _Quote extends _Container {}

final class _ListItem extends _Container {
  _ListItem(this.contentIndent, {required this.hasContent});

  /// How many columns past the start of the enclosing container's content a
  /// line must be indented to continue this item.
  final int contentIndent;

  /// Whether a line in this item has held text. An item that starts with a
  /// blank line ends at the next blank line.
  bool hasContent;
}

/// An open fenced code block.
@immutable
final class _Fence {
  const _Fence({required this.char, required this.length, required this.depth});

  /// The fence character, a backtick or a tilde.
  final int char;

  /// How many fence characters opened the block. A closing fence needs at
  /// least as many.
  final int length;

  /// How many containers hold the block. A line that does not continue all of
  /// them ends it.
  final int depth;
}

/// The first character after the indentation at a position in a line.
@immutable
final class _Indent {
  const _Indent(this.pos, this.column);

  /// The offset of the first character that is not a space or a tab.
  final int pos;

  /// The column of [pos], counting from the start of the line.
  final int column;
}

/// A line of the source, as offsets.
@immutable
final class _Line {
  const _Line(this.start, this.end, this.contentEnd);

  final int start;

  /// The offset after the line ending.
  final int end;

  /// The offset of the line ending, or of [end] on a last line without one.
  final int contentEnd;
}

class _BlockScanner {
  _BlockScanner(this._file, this._start) : _source = _file.getText(0);

  final SourceFile _file;
  final int _start;
  final String _source;
  final _text = StringBuffer();
  final _blocks = <FileSpan>[];

  /// The open containers, outermost first.
  final _containers = <_Container>[];
  _Fence? _fence;
  int? _paragraphStart;

  // Where the scan of the current line is: an offset, its column, and the
  // column where the content of the innermost container seen so far starts.
  int _pos = 0;
  int _column = 0;
  int _base = 0;

  MarkdownBlocks scan() {
    _text.write(_blank(0, _start));
    int lineStart = _start;
    while (lineStart < _source.length) {
      final int newlineAt = _source.indexOf('\n', lineStart);
      final int lineEnd = newlineAt == -1 ? _source.length : newlineAt + 1;
      _scanLine(_Line(lineStart, lineEnd, _contentEnd(lineStart, lineEnd)));
      lineStart = lineEnd;
    }
    _endParagraph(_source.length);
    return MarkdownBlocks(text: _text.toString(), blocks: _blocks);
  }

  void _scanLine(_Line line) {
    _pos = line.start;
    _column = 0;
    _base = 0;
    final int matched = _matchContainers(line);
    if (_fence case final _Fence fence?) {
      if (matched >= fence.depth) {
        if (_closesFence(line, fence)) {
          _fence = null;
        }
        _writeBlank(line);
        return;
      }
      _fence = null;
    }
    final List<_Container> opened = _openContainers(line, matched);
    final bool leavesContainers = matched < _containers.length;
    if (leavesContainers && opened.isEmpty && _continuesLazily(line)) {
      _writeText(line);
      return;
    }
    if (leavesContainers || opened.isNotEmpty) {
      _endParagraph(line.start);
      _containers
        ..removeRange(matched, _containers.length)
        ..addAll(opened);
    }
    _scanLeaf(line);
  }

  /// Steps past the markers and indentation of each open container that
  /// [line] continues, and returns how many it continues.
  int _matchContainers(_Line line) {
    for (var i = 0; i < _containers.length; i++) {
      final bool continues = switch (_containers[i]) {
        _Quote() => _stepPastQuoteMarker(line),
        final _ListItem item => _stepIntoListItem(line, item),
      };
      if (!continues) {
        return i;
      }
    }
    return _containers.length;
  }

  bool _stepIntoListItem(_Line line, _ListItem item) {
    final _Indent indent = _indentAt(_pos, _column);
    if (indent.pos >= line.contentEnd) {
      return item.hasContent;
    }
    if (indent.column - _base < item.contentIndent) {
      return false;
    }
    _base += item.contentIndent;
    _advanceToColumn(_base);
    return true;
  }

  /// Steps past a `>` and the one space after it, if [line] has one after at
  /// most 3 columns of indentation.
  bool _stepPastQuoteMarker(_Line line) {
    final _Indent indent = _indentAt(_pos, _column);
    if (indent.column - _base > 3 ||
        indent.pos >= line.contentEnd ||
        _source.codeUnitAt(indent.pos) != greaterThan) {
      return false;
    }
    _pos = indent.pos + 1;
    _column = indent.column + 1;
    _base = _column;
    if (_pos < line.contentEnd && isSpaceOrTab(_source.codeUnitAt(_pos))) {
      _base++;
      _stepOneColumn();
    }
    return true;
  }

  /// Steps past the blockquote and list item markers that start new
  /// containers on [line], and returns the new containers.
  List<_Container> _openContainers(_Line line, int matched) {
    final opened = <_Container>[];
    while (true) {
      final _Indent indent = _indentAt(_pos, _column);
      if (indent.column - _base >= 4 || indent.pos >= line.contentEnd) {
        break;
      }
      if (_stepPastQuoteMarker(line)) {
        opened.add(_Quote());
        continue;
      }
      final bool mayInterruptParagraph = !_mustNotInterruptParagraph(matched, opened);
      final _ListItem? item = _stepPastListMarker(line, indent, mayInterruptParagraph);
      if (item == null) {
        break;
      }
      opened.add(item);
    }
    return opened;
  }

  /// Whether a new list item here would be the first in its list and would
  /// interrupt a paragraph. CommonMark then allows only a non-empty item that
  /// is a bullet or numbered 1, so a hard-wrapped line such as
  /// `2. Configuration` continues the paragraph.
  bool _mustNotInterruptParagraph(int matched, List<_Container> opened) =>
      _paragraphStart != null &&
      opened.isEmpty &&
      !_containers.skip(matched).any((container) => container is _ListItem);

  _ListItem? _stepPastListMarker(_Line line, _Indent indent, bool mayInterruptParagraph) {
    final int markerEnd = _listMarkerEnd(line, indent.pos);
    if (markerEnd == -1 || _isThematicBreak(line, indent.pos)) {
      return null;
    }
    final int markerChar = _source.codeUnitAt(indent.pos);
    final bool isOrderedNotOne =
        isDigit(markerChar) && int.parse(_source.substring(indent.pos, markerEnd - 1)) != 1;
    final int markerEndColumn = indent.column + markerEnd - indent.pos;
    final _Indent content = _indentAt(markerEnd, markerEndColumn);
    final bool isEmpty = content.pos >= line.contentEnd;
    if (!mayInterruptParagraph && (isEmpty || isOrderedNotOne)) {
      return null;
    }
    // Content 5 or more columns past the marker is an indented code block
    // inside the item, whose content then starts 1 column past the marker.
    final int contentColumn = isEmpty || content.column - markerEndColumn > 4
        ? markerEndColumn + 1
        : content.column;
    _pos = markerEnd;
    _column = markerEndColumn;
    _advanceToColumn(contentColumn);
    final int contentIndent = contentColumn - _base;
    _base = contentColumn;
    return _ListItem(contentIndent, hasContent: !isEmpty);
  }

  /// The offset after the list item marker at [pos] (`-`, `+`, `*`, or 1 to 9
  /// digits and `.` or `)`), or -1 when [pos] starts none. A marker must be
  /// followed by a space, a tab or the line ending.
  int _listMarkerEnd(_Line line, int pos) {
    final int char = _source.codeUnitAt(pos);
    int end = pos + 1;
    if (isDigit(char)) {
      while (end < line.contentEnd && end - pos < 10 && isDigit(_source.codeUnitAt(end))) {
        end++;
      }
      if (end >= line.contentEnd || end - pos > 9) {
        return -1;
      }
      final int delimiter = _source.codeUnitAt(end);
      if (delimiter != period && delimiter != closeParen) {
        return -1;
      }
      end++;
    } else if (char != hyphen && char != plus && char != asterisk) {
      return -1;
    }
    if (end < line.contentEnd && !isSpaceOrTab(_source.codeUnitAt(end))) {
      return -1;
    }
    return end;
  }

  /// Whether [line], whose open containers did not all continue, adds to the
  /// open paragraph instead of starting a block.
  bool _continuesLazily(_Line line) {
    if (_paragraphStart == null) {
      return false;
    }
    final _Indent indent = _indentAt(_pos, _column);
    if (indent.pos >= line.contentEnd) {
      return false;
    }
    if (indent.column - _base >= 4) {
      return true;
    }
    return _fenceAt(line, indent.pos) == null &&
        !_isAtxHeading(line, indent.pos) &&
        !_isThematicBreak(line, indent.pos);
  }

  /// Reads the rest of [line], after its container markers, as a blank line,
  /// a code block, a heading, a thematic break or paragraph text.
  void _scanLeaf(_Line line) {
    final _Indent indent = _indentAt(_pos, _column);
    if (indent.pos >= line.contentEnd) {
      _endParagraph(line.start);
      _writeBlank(line);
      return;
    }
    if (_containers.lastOrNull case final _ListItem item) {
      item.hasContent = true;
    }
    if (indent.column - _base >= 4) {
      // An indented code block cannot interrupt a paragraph.
      if (_paragraphStart == null) {
        _writeBlank(line);
      } else {
        _writeText(line);
      }
      return;
    }
    if (_fenceAt(line, indent.pos) case final _Fence fence?) {
      _endParagraph(line.start);
      _fence = fence;
      _writeBlank(line);
    } else if (_isAtxHeading(line, indent.pos)) {
      _endParagraph(line.start);
      _paragraphStart = line.start;
      _writeText(line);
      _endParagraph(line.end);
    } else if (_isThematicBreak(line, indent.pos) ||
        (_paragraphStart != null && _isSetextUnderline(line, indent.pos))) {
      _endParagraph(line.start);
      _writeBlank(line);
    } else {
      _paragraphStart ??= line.start;
      _writeText(line);
    }
  }

  /// The fenced code block that a run of 3 or more backticks or tildes at
  /// [pos] opens, or `null`. A backtick fence's info string cannot hold a
  /// backtick, because the line is then a code span.
  _Fence? _fenceAt(_Line line, int pos) {
    final int char = _source.codeUnitAt(pos);
    if (char != backtick && char != tilde) {
      return null;
    }
    final int runEnd = _runEnd(pos, line.contentEnd, char);
    if (runEnd - pos < 3) {
      return null;
    }
    if (char == backtick && _source.substring(runEnd, line.contentEnd).contains('`')) {
      return null;
    }
    return _Fence(char: char, length: runEnd - pos, depth: _containers.length);
  }

  /// Whether [line] is a closing fence for [fence]: the same character, at
  /// least as many of it, at most 3 columns of indentation, and nothing after.
  bool _closesFence(_Line line, _Fence fence) {
    final _Indent indent = _indentAt(_pos, _column);
    if (indent.column - _base >= 4 ||
        indent.pos >= line.contentEnd ||
        _source.codeUnitAt(indent.pos) != fence.char) {
      return false;
    }
    final int runEnd = _runEnd(indent.pos, line.contentEnd, fence.char);
    return runEnd - indent.pos >= fence.length && _isBlank(runEnd, line.contentEnd);
  }

  /// Whether 1 to 6 `#` at [pos] start an ATX heading.
  bool _isAtxHeading(_Line line, int pos) {
    final int runEnd = _runEnd(pos, line.contentEnd, hash);
    final int length = runEnd - pos;
    return length >= 1 &&
        length <= 6 &&
        (runEnd == line.contentEnd || isSpaceOrTab(_source.codeUnitAt(runEnd)));
  }

  /// Whether the rest of [line] from [pos] is 3 or more of the same `-`, `*`
  /// or `_`, with only spaces and tabs between them.
  bool _isThematicBreak(_Line line, int pos) {
    final int char = _source.codeUnitAt(pos);
    if (char != hyphen && char != asterisk && char != underscore) {
      return false;
    }
    var count = 0;
    for (var i = pos; i < line.contentEnd; i++) {
      final int current = _source.codeUnitAt(i);
      if (current == char) {
        count++;
      } else if (!isSpaceOrTab(current)) {
        return false;
      }
    }
    return count >= 3;
  }

  /// Whether the rest of [line] from [pos] is a run of `=` or `-` and
  /// trailing spaces, which makes the paragraph before it a heading.
  bool _isSetextUnderline(_Line line, int pos) {
    final int char = _source.codeUnitAt(pos);
    if (char != equals && char != hyphen) {
      return false;
    }
    return _isBlank(_runEnd(pos, line.contentEnd, char), line.contentEnd);
  }

  /// The first character at or after [pos] that is not a space or a tab,
  /// where [pos] is at [column].
  _Indent _indentAt(int pos, int column) {
    var i = pos;
    var col = column;
    while (i < _source.length) {
      final int char = _source.codeUnitAt(i);
      if (char == space) {
        col++;
      } else if (char == tab) {
        col = _nextTabStop(col);
      } else {
        break;
      }
      i++;
    }
    return _Indent(i, col);
  }

  /// Steps past spaces and tabs until the scan reaches [column]. A tab that
  /// crosses [column] is stepped past, and its extra columns count as
  /// indentation of the content after it.
  void _advanceToColumn(int column) {
    while (_column < column && _pos < _source.length && isSpaceOrTab(_source.codeUnitAt(_pos))) {
      _stepOneColumn();
    }
  }

  void _stepOneColumn() {
    _column = _source.codeUnitAt(_pos) == tab ? _nextTabStop(_column) : _column + 1;
    _pos++;
  }

  void _writeText(_Line line) => _text
    ..write(_blank(line.start, _pos))
    ..write(_source.substring(_pos, line.end));

  void _writeBlank(_Line line) => _text.write(_blank(line.start, line.end));

  /// The source from [start] to [end] with every character but line endings
  /// replaced by a space.
  String _blank(int start, int end) {
    final buffer = StringBuffer();
    for (var i = start; i < end; i++) {
      final int char = _source.codeUnitAt(i);
      buffer.writeCharCode(char == newline || char == carriageReturn ? char : space);
    }
    return buffer.toString();
  }

  void _endParagraph(int end) {
    if (_paragraphStart case final int start) {
      _blocks.add(_file.span(start, end));
    }
    _paragraphStart = null;
  }

  bool _isBlank(int start, int end) {
    for (var i = start; i < end; i++) {
      if (!isSpaceOrTab(_source.codeUnitAt(i))) {
        return false;
      }
    }
    return true;
  }

  int _runEnd(int start, int end, int char) {
    var i = start;
    while (i < end && _source.codeUnitAt(i) == char) {
      i++;
    }
    return i;
  }

  int _contentEnd(int lineStart, int lineEnd) {
    var end = lineEnd;
    if (end > lineStart && _source.codeUnitAt(end - 1) == newline) {
      end--;
    }
    if (end > lineStart && _source.codeUnitAt(end - 1) == carriageReturn) {
      end--;
    }
    return end;
  }
}

int _nextTabStop(int column) => column + 4 - column % 4;
