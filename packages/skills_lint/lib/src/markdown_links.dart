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
/// with offsets
/// into [markdown] that start at [offset].
///
/// The scanner follows CommonMark for what matters to path checks: it skips
/// code spans and fenced and indented code blocks, reads `<...>`
/// destinations, and allows balanced parentheses in a destination. It does
/// not read reference-style links.
List<MarkdownLink> markdownLinksIn(String markdown, {int offset = 0}) {
  final links = <MarkdownLink>[];
  final scanner = _InlineScanner(markdown, offset, links);
  for (final (int start, int end) in _proseRanges(markdown)) {
    scanner.scan(start, end);
  }
  return links;
}

final RegExp _fencePattern = RegExp(r'^( *)(`{3,}|~{3,})');
final RegExp _listItemPattern = RegExp(r'^ {0,3}(?:[-+*]|\d{1,9}[.)])(?:[ \t]|$)');

/// The ranges of [markdown] outside fenced and indented code blocks.
///
/// Inside a list, an indented line continues the list item rather than
/// starting a code block, and a fence may be indented to the item's content.
List<(int, int)> _proseRanges(String markdown) {
  final ranges = <(int, int)>[];
  int? proseStart = 0;
  String? fence;
  var previousBlank = true;
  var inIndentedCode = false;
  var inList = false;
  var lineStart = 0;
  while (lineStart < markdown.length) {
    final int newline = markdown.indexOf('\n', lineStart);
    final int lineEnd = newline == -1 ? markdown.length : newline + 1;
    final String line = markdown.substring(lineStart, lineEnd).replaceAll('\t', '    ');
    final bool blank = line.trim().isEmpty;
    final int indent = line.length - line.trimLeft().length;

    var inCode = false;
    if (fence != null) {
      inCode = true;
      final RegExpMatch? close = _fencePattern.firstMatch(line);
      if (close != null &&
          close[2]![0] == fence[0] &&
          close[2]!.length >= fence.length &&
          line.substring(close.end).trim().isEmpty) {
        fence = null;
      }
    } else if (_fencePattern.firstMatch(line) case final RegExpMatch open
        when (inList || open[1]!.length <= 3) &&
            !(open[2]![0] == '`' && line.substring(open.end).contains('`'))) {
      inCode = true;
      fence = open[2];
      inIndentedCode = false;
    } else if (!blank && indent >= 4 && !inList && (previousBlank || inIndentedCode)) {
      inCode = true;
      inIndentedCode = true;
    } else if (!blank) {
      inIndentedCode = false;
      if (_listItemPattern.hasMatch(line)) {
        inList = true;
      } else if (indent == 0 && previousBlank) {
        inList = false;
      }
    }

    if (inCode && proseStart != null) {
      ranges.add((proseStart, lineStart));
      proseStart = null;
    } else if (!inCode && proseStart == null) {
      proseStart = lineStart;
    }
    // A blank line inside an indented code block keeps the block open.
    if (!(blank && inIndentedCode)) {
      previousBlank = blank;
    }
    lineStart = lineEnd;
  }
  if (proseStart != null) {
    ranges.add((proseStart, markdown.length));
  }
  return ranges;
}

class _InlineScanner {
  _InlineScanner(this._text, this._offset, this._links);

  final String _text;
  final int _offset;
  final List<MarkdownLink> _links;

  static final RegExp _paragraphBreak = RegExp(r'\n[ \t]*\n');

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
      if (char == _newline && _paragraphBreak.matchAsPrefix(_text, i) != null) {
        return null;
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
    var i = _skipSpace(start, end);
    final int targetStart;
    final int targetEnd;
    final bool angleBracketed = i < end && _text.codeUnitAt(i) == _lessThan;
    if (angleBracketed && _text.codeUnitAt(i) == _lessThan) {
      targetStart = i + 1;
      i = targetStart;
      while (i < end) {
        final int char = _text.codeUnitAt(i);
        if (char == _backslash) {
          i += 2;
        } else if (char == _greaterThan) {
          break;
        } else if (char == _lessThan || char == _newline) {
          return null;
        } else {
          i++;
        }
      }
      if (i >= end) {
        return null;
      }
      targetEnd = i;
      i++;
    } else {
      targetStart = i;
      var depth = 0;
      while (i < end) {
        final int char = _text.codeUnitAt(i);
        if (char == _backslash && i + 1 < end) {
          i += 2;
        } else if (char <= _space) {
          break;
        } else if (char == _openParen) {
          depth++;
          i++;
        } else if (char == _closeParen) {
          if (depth == 0) {
            break;
          }
          depth--;
          i++;
        } else {
          i++;
        }
      }
      if (depth != 0) {
        return null;
      }
      targetEnd = i;
    }
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
    var i = start + 1;
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
