// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// An inline Markdown link or image, such as `[text](target "title")`.
class MarkdownLink {
  const MarkdownLink({
    required this.start,
    required this.targetStart,
    required this.target,
    required this.isAngleBracketed,
  });

  /// The offset of the `[` that opens the link text.
  final int start;

  /// The offset of [target] in the scanned text, after any `<`.
  final int targetStart;

  /// The link destination as written, without `<` and `>` and without a
  /// title.
  final String target;

  /// The offset just after [target].
  int get targetEnd => targetStart + target.length;

  /// Whether `<` and `>` enclose [target].
  final bool isAngleBracketed;
}

/// The inline links and images in [markdown], in the order of their targets,
/// with offsets into [markdown] that start at [offset].
///
/// The scanner follows CommonMark for what matters to path checks: it skips
/// code spans and fenced and indented code blocks, reads `<...>`
/// destinations, and allows balanced parentheses in a destination. It does
/// not read reference-style links.
List<MarkdownLink> markdownLinksIn(String markdown, {int offset = 0}) {
  final links = <MarkdownLink>[];
  final scanner = _InlineScanner(markdown, offset, links);
  for (final (int start, int end) in _BlockScanner(markdown).paragraphs()) {
    scanner.scan(start, end);
  }
  return links;
}

final RegExp _fencePattern = RegExp(r'^( *)(`{3,}|~{3,})');
final RegExp _headingPattern = RegExp(r'^ {0,3}#{1,6}(?:[ \t]|$)');

/// A line with only blockquote markers, which separates paragraphs in a
/// blockquote.
final RegExp _emptyQuotePattern = RegExp(r'^[ >]*$');
final RegExp _listItemPattern = RegExp(r'^ {0,3}(?:[-+*]|\d{1,9}[.)])(?:[ \t]|$)');

/// Splits Markdown into the runs of lines that hold inline content.
///
/// Inside a list, an indented line continues the list item rather than
/// starting a code block, and a fence may be indented to the item's content.
/// A list ends at an unindented line after a blank line.
class _BlockScanner {
  _BlockScanner(this._markdown);

  final String _markdown;

  /// The fence that opened the fenced code block the scanner is in.
  String? _fence;
  bool _previousBlank = true;
  bool _inIndentedCode = false;
  bool _inList = false;

  /// The ranges of the runs of non-blank lines outside code blocks.
  ///
  /// A code span or link never crosses the end of a range.
  List<(int, int)> paragraphs() {
    final ranges = <(int, int)>[];
    int? paragraphStart;
    var lineStart = 0;
    while (lineStart < _markdown.length) {
      final int newline = _markdown.indexOf('\n', lineStart);
      final int lineEnd = newline == -1 ? _markdown.length : newline + 1;
      final String line = _markdown.substring(lineStart, lineEnd).replaceAll('\t', '    ');
      final bool isText = _isTextLine(line);
      final bool isHeading = isText && _headingPattern.hasMatch(line);
      // A list item and a heading each start their own block.
      final bool startsBlock = isHeading || (isText && _listItemPattern.hasMatch(line));
      if ((!isText || startsBlock) && paragraphStart != null) {
        ranges.add((paragraphStart, lineStart));
        paragraphStart = null;
      }
      if (isHeading) {
        ranges.add((lineStart, lineEnd));
      } else if (isText) {
        paragraphStart ??= lineStart;
      }
      lineStart = lineEnd;
    }
    if (paragraphStart != null) {
      ranges.add((paragraphStart, _markdown.length));
    }
    return ranges;
  }

  /// Whether [line] holds inline content, and not code or blank space.
  bool _isTextLine(String line) {
    final bool blank = _emptyQuotePattern.hasMatch(line.trim());
    final bool isCode = _fence != null ? _continuesFence(line) : _startsCode(line, blank: blank);
    // A blank line inside an indented code block keeps the block open.
    if (!(blank && _inIndentedCode)) {
      _previousBlank = blank;
    }
    return !isCode && !blank;
  }

  /// Whether [line], inside a fenced code block, is code. A closing fence
  /// ends the block and counts as code.
  bool _continuesFence(String line) {
    final String fence = _fence!;
    final RegExpMatch? close = _fencePattern.firstMatch(line);
    if (close != null &&
        close[2]![0] == fence[0] &&
        close[2]!.length >= fence.length &&
        line.substring(close.end).trim().isEmpty) {
      _fence = null;
    }
    return true;
  }

  /// Whether [line], outside a fenced code block, opens a fenced code block
  /// or is part of an indented one.
  bool _startsCode(String line, {required bool blank}) {
    final int indent = line.length - line.trimLeft().length;
    if (_fencePattern.firstMatch(line) case final RegExpMatch open
        when (_inList || open[1]!.length <= 3) &&
            !(open[2]![0] == '`' && line.substring(open.end).contains('`'))) {
      _fence = open[2];
      _inIndentedCode = false;
      return true;
    }
    if (blank) {
      return false;
    }
    if (indent >= 4 && !_inList && (_previousBlank || _inIndentedCode)) {
      _inIndentedCode = true;
      return true;
    }
    _inIndentedCode = false;
    if (_listItemPattern.hasMatch(line)) {
      _inList = true;
    } else if (indent == 0 && _previousBlank) {
      _inList = false;
    }
    return false;
  }
}

class _InlineScanner {
  _InlineScanner(this._text, this._offset, this._links);

  final String _text;
  final int _offset;
  final List<MarkdownLink> _links;

  void scan(int start, int end) {
    var i = start;
    while (i < end) {
      final int char = _text.codeUnitAt(i);
      if (char == _backslash) {
        i += 2;
      } else if (char == _backtick) {
        i = _afterCodeSpan(i, end);
      } else if (char == _openBracket) {
        i = _afterLink(i, end);
      } else {
        i++;
      }
    }
  }

  /// The offset after the code span that opens at [start], or after the
  /// backtick run at [start] when no run of the same length closes it.
  int _afterCodeSpan(int start, int end) {
    final int runEnd = _runEnd(start, end, _backtick);
    final int length = runEnd - start;
    var i = runEnd;
    while (i < end) {
      final int close = _text.indexOf('`', i);
      if (close == -1 || close >= end) {
        break;
      }
      final int closeEnd = _runEnd(close, end, _backtick);
      if (closeEnd - close == length) {
        return closeEnd;
      }
      i = closeEnd;
    }
    return runEnd;
  }

  int _runEnd(int start, int end, int char) {
    var i = start;
    while (i < end && _text.codeUnitAt(i) == char) {
      i++;
    }
    return i;
  }

  /// Records the link that opens at [start], if any, and returns the offset
  /// to continue scanning from.
  int _afterLink(int start, int end) {
    final int textStart = start + 1;
    final int? textEnd = _closingBracket(textStart, end);
    if (textEnd == null || textEnd + 1 >= end || _text.codeUnitAt(textEnd + 1) != _openParen) {
      return textStart;
    }
    final (MarkdownLink, int)? parsed = _destination(start, textEnd + 2, end);
    if (parsed == null) {
      return textStart;
    }
    final (MarkdownLink link, int linkEnd) = parsed;
    // Link text may hold an image, such as `[![logo](logo.png)](page.md)`.
    // Scanning it first keeps the links in the order of their targets.
    scan(textStart, textEnd);
    _links.add(link);
    return linkEnd;
  }

  /// The offset of the `]` that closes link text starting at [start].
  int? _closingBracket(int start, int end) {
    var depth = 0;
    var i = start;
    while (i < end) {
      final int char = _text.codeUnitAt(i);
      if (char == _backslash) {
        i += 2;
        continue;
      }
      if (char == _backtick) {
        i = _afterCodeSpan(i, end);
        continue;
      }
      if (char == _openBracket) {
        depth++;
      } else if (char == _closeBracket) {
        if (depth == 0) {
          return i;
        }
        depth--;
      }
      i++;
    }
    return null;
  }

  /// The link opening at [linkStart] whose destination follows the `(` at
  /// [start] - 1, with the offset after its `)`.
  (MarkdownLink, int)? _destination(int linkStart, int start, int end) {
    int i = _skipSpace(start, end);
    final bool angleBracketed = i < end && _text.codeUnitAt(i) == _lessThan;
    final int targetStart = angleBracketed ? i + 1 : i;
    final int? targetEnd = angleBracketed
        ? _angleTargetEnd(targetStart, end)
        : _bareTargetEnd(targetStart, end);
    if (targetEnd == null) {
      return null;
    }
    // Step past the closing >.
    i = angleBracketed ? targetEnd + 1 : targetEnd;
    i = _skipSpace(i, end);
    if (i < end && i > targetEnd) {
      final int? titleEnd = _titleEnd(i, end);
      if (titleEnd != null) {
        i = _skipSpace(titleEnd, end);
      }
    }
    if (i >= end || _text.codeUnitAt(i) != _closeParen) {
      return null;
    }
    final link = MarkdownLink(
      start: _offset + linkStart,
      targetStart: _offset + targetStart,
      target: _text.substring(targetStart, targetEnd),
      isAngleBracketed: angleBracketed,
    );
    return (link, i + 1);
  }

  /// The offset of the `>` that closes a destination starting at [start].
  int? _angleTargetEnd(int start, int end) {
    var i = start;
    while (i < end) {
      final int char = _text.codeUnitAt(i);
      if (char == _backslash) {
        i += 2;
      } else if (char == _greaterThan) {
        return i;
      } else if (char == _lessThan || char == _newline) {
        return null;
      } else {
        i++;
      }
    }
    return null;
  }

  /// The offset after a destination without `<` that starts at [start], or
  /// null if its parentheses are unbalanced.
  int? _bareTargetEnd(int start, int end) {
    var i = start;
    var depth = 0;
    while (i < end) {
      final int char = _text.codeUnitAt(i);
      if (char == _backslash && i + 1 < end) {
        i += 2;
        continue;
      }
      if (char <= _space || (char == _closeParen && depth == 0)) {
        break;
      }
      if (char == _openParen) {
        depth++;
      } else if (char == _closeParen) {
        depth--;
      }
      i++;
    }
    return depth == 0 ? i : null;
  }

  /// The offset after the title that opens at [start], if one does.
  int? _titleEnd(int start, int end) {
    final int open = _text.codeUnitAt(start);
    final int close = switch (open) {
      _doubleQuote || _singleQuote => open,
      _openParen => _closeParen,
      _ => -1,
    };
    if (close == -1) {
      return null;
    }
    int i = start + 1;
    while (i < end) {
      final int char = _text.codeUnitAt(i);
      if (char == _backslash) {
        i += 2;
      } else if (char == close) {
        return i + 1;
      } else if (open == _openParen && char == _openParen) {
        return null;
      } else {
        i++;
      }
    }
    return null;
  }

  /// The offset after spaces, tabs and at most one line ending from [start].
  int _skipSpace(int start, int end) {
    var i = start;
    var newlines = 0;
    while (i < end) {
      final int char = _text.codeUnitAt(i);
      if (char == _newline) {
        if (++newlines > 1) {
          break;
        }
      } else if (char != _space && char != _tab && char != _carriageReturn) {
        break;
      }
      i++;
    }
    return i;
  }
}

const int _tab = 0x09;
const int _newline = 0x0A;
const int _carriageReturn = 0x0D;
const int _space = 0x20;
const int _doubleQuote = 0x22;
const int _singleQuote = 0x27;
const int _openParen = 0x28;
const int _closeParen = 0x29;
const int _lessThan = 0x3C;
const int _greaterThan = 0x3E;
const int _openBracket = 0x5B;
const int _backslash = 0x5C;
const int _closeBracket = 0x5D;
const int _backtick = 0x60;
