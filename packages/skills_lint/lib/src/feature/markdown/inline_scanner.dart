// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:meta/meta.dart';
import 'package:source_span/source_span.dart';

import 'char_codes.dart';
import 'link_models.dart';

/// The most characters a link label can hold between its brackets.
///
/// CommonMark sets this limit (https://spec.commonmark.org/0.31.2/#link-label)
/// so that a `[` with no matching `]` cannot make a parser scan the rest of
/// the document.
@visibleForTesting
const int maxLinkLabelLength = 999;

/// A link destination that has been read, and the offset after it.
@immutable
final class _ParsedTarget {
  const _ParsedTarget({
    required this.start,
    required this.end,
    required this.isAngleBracketed,
    required this.next,
  });

  /// The offsets of the destination, without enclosing `<` and `>`.
  final int start;
  final int end;
  final bool isAngleBracketed;

  /// The offset after the destination, and after its `>` if it has one.
  final int next;
}

/// A link label in brackets that has been read.
@immutable
final class _ParsedLabel {
  const _ParsedLabel(this.text, this.closeBracket);

  /// The label as written, between the brackets.
  final String text;

  /// The offset of the closing `]`.
  final int closeBracket;
}

/// A `[` or `![` that a later `]` can close to form a link or image.
class _LinkOpener {
  _LinkOpener({required this.bracketIndex, required this.spanStart, required this.isImage});

  final int bracketIndex;
  final int spanStart;
  final bool isImage;

  /// Whether this opener can still form a link. A link cannot hold another
  /// link, so a closed link turns off the link openers before it.
  bool isActive = true;
}

/// Reads links, images and link reference definitions from Markdown text.
///
/// It scans the text that `scanMarkdownBlocks` returns, in which container
/// markers and code blocks are spaces, and makes spans in the source file
/// that text came from.
class MarkdownInlineScanner {
  MarkdownInlineScanner(this._file, this._text);

  final SourceFile _file;
  final String _text;

  /// Reads the link reference definition that starts at [lineStart], the
  /// start of a line, and ends before [end], or returns `null` when there is
  /// none. Its destination and its title can each start on the next line.
  LinkDefinition? parseDefinition(int lineStart, int end) {
    final int labelOpen = _skipSpaceAndTab(lineStart, end);
    final _ParsedLabel? label = _parseLabel(labelOpen, end);
    if (label == null) {
      return null;
    }
    final int colonIndex = label.closeBracket + 1;
    if (colonIndex >= end || _text.codeUnitAt(colonIndex) != colon) {
      return null;
    }
    final int targetStart = _skipSpaceAndOneLineEnding(colonIndex + 1, end);
    if (_isAtLineEnd(targetStart, end)) {
      return null;
    }
    final _ParsedTarget? target = _parseTarget(targetStart, end);
    if (target == null || (!target.isAngleBracketed && target.start == target.end)) {
      return null;
    }
    final int? definitionEnd = _definitionEnd(target.next, end);
    if (definitionEnd == null) {
      return null;
    }
    return LinkDefinition(
      label: normalizeLinkLabel(label.text),
      destination: _destination(target),
      end: definitionEnd,
    );
  }

  /// The offset after a definition whose destination ends at [afterTarget]:
  /// after an optional title on the same or the next line, and after the line
  /// ending. Returns `null` when other text follows the destination.
  int? _definitionEnd(int afterTarget, int end) {
    final int afterSpaces = _skipSpaceAndTab(afterTarget, end);
    if (_isAtLineEnd(afterSpaces, end)) {
      final int nextLine = _afterLineEnding(afterSpaces, end);
      return _lineEndAfterTitle(_skipSpaceAndTab(nextLine, end), end) ?? nextLine;
    }
    if (afterSpaces == afterTarget) {
      // A title must be separated from the destination by whitespace.
      return null;
    }
    return _lineEndAfterTitle(afterSpaces, end);
  }

  int? _lineEndAfterTitle(int titleStart, int end) {
    final int? afterTitle = _titleEnd(titleStart, end);
    if (afterTitle == null) {
      return null;
    }
    final int afterSpaces = _skipSpaceAndTab(afterTitle, end);
    return _isAtLineEnd(afterSpaces, end) ? _afterLineEnding(afterSpaces, end) : null;
  }

  /// Reads the links and images from [start] to [end], resolving reference
  /// links against [definitions], keyed by normalized label.
  ///
  /// Keeps a stack of `[` and `![` openers, as CommonMark's algorithm does
  /// (https://spec.commonmark.org/0.31.2/#phase-2-inline-structure), so
  /// nested brackets such as `[![badge](a.png)](b.md)` resolve in one pass.
  List<MarkdownLink> scanLinks(int start, int end, Map<String, LinkDestination> definitions) {
    final links = <MarkdownLink>[];
    final openers = <_LinkOpener>[];
    var i = start;
    while (i < end) {
      final int char = _text.codeUnitAt(i);
      if (char == backslash) {
        i += 2;
      } else if (char == backtick) {
        i = _afterCodeSpan(i, end);
      } else if (char == exclamation && i + 1 < end && _text.codeUnitAt(i + 1) == openBracket) {
        openers.add(_LinkOpener(bracketIndex: i + 1, spanStart: i, isImage: true));
        i += 2;
      } else if (char == openBracket) {
        openers.add(_LinkOpener(bracketIndex: i, spanStart: i, isImage: false));
        i++;
      } else if (char == closeBracket) {
        i = _closeBracketAt(i, end, openers, definitions, links);
      } else {
        i++;
      }
    }
    return links;
  }

  /// Handles the `]` at [closeIndex], adds the link it closes to [links],
  /// and returns the offset to scan from next.
  int _closeBracketAt(
    int closeIndex,
    int end,
    List<_LinkOpener> openers,
    Map<String, LinkDestination> definitions,
    List<MarkdownLink> links,
  ) {
    final _LinkOpener? opener = openers.isEmpty ? null : openers.removeLast();
    if (opener == null || !opener.isActive) {
      return closeIndex + 1;
    }
    final MarkdownLink? link =
        _inlineLink(opener, closeIndex, end) ??
        _referenceLink(opener, closeIndex, end, definitions);
    if (link == null) {
      return closeIndex + 1;
    }
    links.add(link);
    if (!opener.isImage) {
      for (final earlier in openers) {
        if (!earlier.isImage) {
          earlier.isActive = false;
        }
      }
    }
    return link.span.end.offset;
  }

  /// The inline link `[text](destination "title")` whose text ends at
  /// [closeIndex], or `null`.
  MarkdownLink? _inlineLink(_LinkOpener opener, int closeIndex, int end) {
    final int openParenIndex = closeIndex + 1;
    if (openParenIndex >= end || _text.codeUnitAt(openParenIndex) != openParen) {
      return null;
    }
    final int targetStart = _skipSpaceAndOneLineEnding(openParenIndex + 1, end);
    if (targetStart >= end) {
      return null;
    }
    final _ParsedTarget? target = _parseTarget(targetStart, end);
    if (target == null) {
      return null;
    }
    int closeParenIndex = _skipSpaceAndOneLineEnding(target.next, end);
    final bool hasTitle =
        closeParenIndex > target.next &&
        closeParenIndex < end &&
        _text.codeUnitAt(closeParenIndex) != closeParen;
    if (hasTitle) {
      final int? afterTitle = _titleEnd(closeParenIndex, end);
      if (afterTitle == null) {
        return null;
      }
      closeParenIndex = _skipSpaceAndOneLineEnding(afterTitle, end);
    }
    if (closeParenIndex >= end || _text.codeUnitAt(closeParenIndex) != closeParen) {
      return null;
    }
    return MarkdownLink(
      span: _file.span(opener.spanStart, closeParenIndex + 1),
      destination: _destination(target),
    );
  }

  /// The reference link whose text ends at [closeIndex], or `null`: a full
  /// reference `[text][label]`, a collapsed reference `[label][]`, or a
  /// shortcut reference `[label]`.
  MarkdownLink? _referenceLink(
    _LinkOpener opener,
    int closeIndex,
    int end,
    Map<String, LinkDestination> definitions,
  ) {
    if (definitions.isEmpty) {
      return null;
    }
    final int afterClose = closeIndex + 1;
    final String? ownLabel = _labelBetween(opener.bracketIndex, closeIndex);
    LinkDestination? destination;
    var linkEnd = afterClose;
    if (afterClose + 1 < end &&
        _text.codeUnitAt(afterClose) == openBracket &&
        _text.codeUnitAt(afterClose + 1) == closeBracket) {
      destination = ownLabel == null ? null : definitions[ownLabel];
      linkEnd = afterClose + 2;
    } else if (_parseLabel(afterClose, end) case final _ParsedLabel reference?) {
      // When the label is not defined, `[text]` is not read as a shortcut.
      destination = definitions[normalizeLinkLabel(reference.text)];
      linkEnd = reference.closeBracket + 1;
    } else {
      destination = ownLabel == null ? null : definitions[ownLabel];
    }
    if (destination == null) {
      return null;
    }
    return MarkdownLink(span: _file.span(opener.spanStart, linkEnd), destination: destination);
  }

  /// The normalized label between the `[` at [openIndex] and the `]` at
  /// [closeIndex], or `null` when the text there is not a valid label.
  String? _labelBetween(int openIndex, int closeIndex) {
    final _ParsedLabel? label = _parseLabel(openIndex, closeIndex + 1);
    return label != null && label.closeBracket == closeIndex
        ? normalizeLinkLabel(label.text)
        : null;
  }

  LinkDestination _destination(_ParsedTarget target) => LinkDestination(
    _file.span(target.start, target.end),
    isAngleBracketed: target.isAngleBracketed,
  );

  /// Reads a destination at [start]: in `<` and `>`, or bare.
  ///
  /// Backslash escapes are kept as written, so ignore subjects match the
  /// text in `SKILL.md` and Windows paths such as `C:\_dir\file.md` keep their
  /// separators.
  _ParsedTarget? _parseTarget(int start, int end) {
    if (start < end && _text.codeUnitAt(start) == lessThan) {
      final int? targetEnd = _angleTargetEnd(start + 1, end);
      return targetEnd == null
          ? null
          : _ParsedTarget(
              start: start + 1,
              end: targetEnd,
              isAngleBracketed: true,
              next: targetEnd + 1,
            );
    }
    final int? targetEnd = _bareTargetEnd(start, end);
    return targetEnd == null
        ? null
        : _ParsedTarget(start: start, end: targetEnd, isAngleBracketed: false, next: targetEnd);
  }

  /// The offset of the `>` that ends an angle-bracketed destination, or
  /// `null` when the line ends or a `<` comes first.
  int? _angleTargetEnd(int start, int end) {
    var i = start;
    while (i < end) {
      final int char = _text.codeUnitAt(i);
      if (char == greaterThan) {
        return i;
      }
      if (char == lessThan || char == newline || char == carriageReturn) {
        return null;
      }
      if (char == backslash) {
        if (i + 1 >= end || _isLineEndingChar(_text.codeUnitAt(i + 1))) {
          return null;
        }
        i++;
      }
      i++;
    }
    return null;
  }

  /// The offset after a bare destination: before the first space, control
  /// character or unmatched `)`. Returns `null` when its parentheses do not
  /// balance.
  int? _bareTargetEnd(int start, int end) {
    var i = start;
    var parenDepth = 0;
    while (i < end) {
      final int char = _text.codeUnitAt(i);
      if (char == backslash && i + 1 < end && isAsciiPunctuation(_text.codeUnitAt(i + 1))) {
        i += 2;
        continue;
      }
      if (char <= space || char == delete || (char == closeParen && parenDepth == 0)) {
        break;
      }
      if (char == openParen) {
        parenDepth++;
      } else if (char == closeParen) {
        parenDepth--;
      }
      i++;
    }
    return parenDepth == 0 ? i : null;
  }

  /// The offset after a title in `"`, `'` or parentheses that starts at
  /// [start], or `null` when there is none.
  int? _titleEnd(int start, int end) {
    if (start >= end) {
      return null;
    }
    final int open = _text.codeUnitAt(start);
    final int close = switch (open) {
      doubleQuote || singleQuote => open,
      openParen => closeParen,
      _ => -1,
    };
    if (close == -1) {
      return null;
    }
    int i = start + 1;
    while (i < end) {
      final int char = _text.codeUnitAt(i);
      if (char == close) {
        return i + 1;
      }
      if (open == openParen && char == openParen) {
        return null;
      }
      i += char == backslash ? 2 : 1;
    }
    return null;
  }

  /// Reads the label in brackets at [labelOpen], or returns `null` when
  /// there is no `]` within [maxLinkLabelLength] characters, a `[` comes
  /// first, or the label is only whitespace.
  _ParsedLabel? _parseLabel(int labelOpen, int end) {
    if (labelOpen >= end || _text.codeUnitAt(labelOpen) != openBracket) {
      return null;
    }
    final int labelStart = labelOpen + 1;
    final int searchEnd = (labelStart + maxLinkLabelLength + 1).clamp(0, end);
    var hasNonWhitespace = false;
    var i = labelStart;
    while (i < searchEnd) {
      final int char = _text.codeUnitAt(i);
      if (char == closeBracket) {
        return hasNonWhitespace ? _ParsedLabel(_text.substring(labelStart, i), i) : null;
      }
      if (char == openBracket) {
        return null;
      }
      hasNonWhitespace = hasNonWhitespace || !isAsciiWhitespace(char);
      i += char == backslash ? 2 : 1;
    }
    return null;
  }

  /// The offset after the code span that starts with the backticks at
  /// [start], or after those backticks when no run of the same length closes
  /// them.
  int _afterCodeSpan(int start, int end) {
    final int openEnd = _runEnd(start, end, backtick);
    final int length = openEnd - start;
    var i = openEnd;
    while (i < end) {
      final int close = _text.indexOf('`', i);
      if (close == -1 || close >= end) {
        break;
      }
      final int closeEnd = _runEnd(close, end, backtick);
      if (closeEnd - close == length) {
        return closeEnd;
      }
      i = closeEnd;
    }
    return openEnd;
  }

  int _runEnd(int start, int end, int char) {
    var i = start;
    while (i < end && _text.codeUnitAt(i) == char) {
      i++;
    }
    return i;
  }

  int _skipSpaceAndTab(int start, int end) {
    var i = start;
    while (i < end && isSpaceOrTab(_text.codeUnitAt(i))) {
      i++;
    }
    return i;
  }

  /// The offset after spaces, tabs and at most one line ending from [start].
  int _skipSpaceAndOneLineEnding(int start, int end) {
    var i = start;
    var newlines = 0;
    while (i < end) {
      final int char = _text.codeUnitAt(i);
      if (char == newline) {
        newlines++;
        if (newlines > 1) {
          break;
        }
      } else if (!isSpaceOrTab(char) && char != carriageReturn) {
        break;
      }
      i++;
    }
    return i;
  }

  bool _isAtLineEnd(int pos, int end) {
    if (pos >= end) {
      return true;
    }
    final int char = _text.codeUnitAt(pos);
    return char == newline ||
        (char == carriageReturn && pos + 1 < end && _text.codeUnitAt(pos + 1) == newline);
  }

  int _afterLineEnding(int pos, int end) {
    var i = pos;
    if (i < end && _text.codeUnitAt(i) == carriageReturn) {
      i++;
    }
    if (i < end && _text.codeUnitAt(i) == newline) {
      i++;
    }
    return i;
  }
}

/// [label] with its outer whitespace removed, each inner run of whitespace
/// replaced by one space, and its case folded, so that labels match as
/// CommonMark requires (https://spec.commonmark.org/0.31.2/#matches).
@visibleForTesting
String normalizeLinkLabel(String label) {
  final buffer = StringBuffer();
  var pendingSpace = false;
  for (final int char in label.codeUnits) {
    if (isAsciiWhitespace(char)) {
      pendingSpace = buffer.isNotEmpty;
    } else {
      if (pendingSpace) {
        buffer.writeCharCode(space);
        pendingSpace = false;
      }
      buffer.writeCharCode(char);
    }
  }
  // Dart's toLowerCase does not fold ß, which Unicode case folding maps to ss.
  return buffer.toString().toLowerCase().replaceAll('ß', 'ss');
}

bool _isLineEndingChar(int char) => char == newline || char == carriageReturn;
