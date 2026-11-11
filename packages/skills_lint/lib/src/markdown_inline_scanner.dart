// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'markdown_block_scanner.dart';

const int _tab = 0x09;
const int _newline = 0x0A;
const int _carriageReturn = 0x0D;
const int _space = 0x20;
const int _exclamation = 0x21;
const int _doubleQuote = 0x22;
const int _singleQuote = 0x27;
const int _openParen = 0x28;
const int _closeParen = 0x29;
const int _colon = 0x3A;
const int _lessThan = 0x3C;
const int _greaterThan = 0x3E;
const int _openBracket = 0x5B;
const int _backslash = 0x5C;
const int _closeBracket = 0x5D;
const int _backtick = 0x60;
const int _tilde = 0x7E;
const int _delete = 0x7F;

/// Maximum characters allowed inside a CommonMark link label (`[...]`).
const int _maxLinkLabelLength = 999;

final RegExp _labelWhitespacePattern = RegExp(r'[ \t\r\n]+');
final RegExp _edgeAsciiWhitespacePattern = RegExp(r'^[ \t\r\n]+|[ \t\r\n]+$');

/// Source slice of a link destination in the scanned Markdown string.
typedef TargetSpan = ({int targetStart, int targetEnd, String target, bool isAngleBracketed});

/// A resolved link or image span paired with its [TargetSpan].
typedef LinkMatch = ({int spanStart, int spanEnd, TargetSpan destination});

/// Consumes leading CommonMark link reference definitions (`[ref]: target`) in
/// [text] at the start of [block], recording the first definition for each
/// normalized label in [definitions] and returning the offset where paragraph
/// inline content begins.
int consumeReferenceDefinitions(
  String text,
  MarkdownTextBlock block,
  Map<String, TargetSpan> definitions,
) {
  int pos = block.start;
  while (pos < block.end) {
    final (String label, TargetSpan target, int nextPos)? parsed = _parseDefinition(
      text,
      pos,
      block.end,
      containers: block.containers,
    );
    if (parsed == null) {
      break;
    }
    final (String label, TargetSpan target, int nextPos) = parsed;
    definitions.putIfAbsent(label, () => target);
    pos = nextPos;
  }
  return pos;
}

(String, TargetSpan, int)? _parseDefinition(
  String text,
  int start,
  int blockEnd, {
  required List<ContainerMarker> containers,
}) {
  final int? labelOpen = _definitionLabelStart(text, start, blockEnd, containers: containers);
  if (labelOpen == null) {
    return null;
  }

  final (String rawLabel, int labelClose)? parsedLabel = _parseLinkLabel(text, labelOpen, blockEnd);
  if (parsedLabel == null) {
    return null;
  }
  final (String rawLabel, int labelClose) = parsedLabel;
  final int colonIndex = labelClose + 1;
  if (colonIndex >= blockEnd || text.codeUnitAt(colonIndex) != _colon) {
    return null;
  }

  final int? destStart = _skipDefinitionSpace(
    text,
    colonIndex + 1,
    blockEnd,
    containers: containers,
  );
  if (destStart == null || destStart >= blockEnd) {
    return null;
  }

  final (TargetSpan target, int afterTarget)? parsedTarget = _parseTarget(
    text,
    destStart,
    blockEnd,
  );
  if (parsedTarget == null) {
    return null;
  }
  final (TargetSpan target, int afterTarget) = parsedTarget;
  if (!target.isAngleBracketed && target.target.isEmpty) {
    return null;
  }

  final int? defEnd = _parseDefinitionTail(text, afterTarget, blockEnd, containers: containers);
  if (defEnd == null) {
    return null;
  }
  return (_normalizeLinkLabel(rawLabel), target, defEnd);
}

int? _definitionLabelStart(
  String text,
  int start,
  int blockEnd, {
  required List<ContainerMarker> containers,
}) {
  final bool atLineStart = start == 0 || text.codeUnitAt(start - 1) == _newline;
  if (!atLineStart) {
    final (int indent, int pos) = leadingIndent(text, start, blockEnd);
    return indent <= 3 && pos < blockEnd && text.codeUnitAt(pos) == _openBracket ? pos : null;
  }
  final int lineEnd = _contentEndOfLine(text, start, blockEnd);
  final (int matched, int column, int afterContainers) = matchContainers(
    text,
    start,
    lineEnd,
    containers,
  );
  if (!onlyListContainersRemain(containers, matched)) {
    return null;
  }
  final (int indent, int pos) = leadingIndent(text, afterContainers, lineEnd, startColumn: column);
  return indent <= 3 && pos < lineEnd && text.codeUnitAt(pos) == _openBracket ? pos : null;
}

int? _parseDefinitionTail(
  String text,
  int afterTarget,
  int blockEnd, {
  required List<ContainerMarker> containers,
}) {
  final int afterSpaces = skipHorizontalSpace(text, afterTarget, blockEnd);
  if (_isAtLineEnd(text, afterSpaces, blockEnd)) {
    final int destLineEnd = _afterLineEnding(text, afterSpaces, blockEnd);
    final int? nextLineTitleEnd = _tryTitleOnNextLine(
      text,
      destLineEnd,
      blockEnd,
      containers: containers,
    );
    return nextLineTitleEnd ?? destLineEnd;
  }
  if (afterSpaces == afterTarget) {
    return null;
  }
  return _lineEndAfterTitle(text, afterSpaces, blockEnd);
}

int? _tryTitleOnNextLine(
  String text,
  int lineStart,
  int blockEnd, {
  required List<ContainerMarker> containers,
}) {
  if (lineStart >= blockEnd) {
    return null;
  }
  final int lineEnd = _contentEndOfLine(text, lineStart, blockEnd);
  final (int matched, _, int afterContainers) = matchContainers(
    text,
    lineStart,
    lineEnd,
    containers,
  );
  if (!onlyListContainersRemain(containers, matched)) {
    return null;
  }
  final int titleStart = skipHorizontalSpace(text, afterContainers, blockEnd);
  return _lineEndAfterTitle(text, titleStart, blockEnd);
}

int? _lineEndAfterTitle(String text, int titleStart, int blockEnd) {
  final int? afterTitle = _parseTitle(text, titleStart, blockEnd);
  if (afterTitle == null) {
    return null;
  }
  final int afterTitleSpaces = skipHorizontalSpace(text, afterTitle, blockEnd);
  if (!_isAtLineEnd(text, afterTitleSpaces, blockEnd)) {
    return null;
  }
  return _afterLineEnding(text, afterTitleSpaces, blockEnd);
}

class _LinkOpener {
  _LinkOpener({required this.bracketIndex, required this.spanStart, required this.isImage});

  final int bracketIndex;
  final int spanStart;
  final bool isImage;
  bool isActive = true;
}

/// Scans non-code text blocks for inline and reference-style links and images,
/// using CommonMark's `[` / `![` opener stack so nested brackets run in linear
/// time and outer `[` openers deactivate when an inner link closes.
class MarkdownInlineScanner {
  MarkdownInlineScanner(this._text, this._definitions, this._matches);

  final String _text;
  final Map<String, TargetSpan> _definitions;
  final List<LinkMatch> _matches;

  void scanRange(int start, int end) {
    final openers = <_LinkOpener>[];
    var i = start;
    while (i < end) {
      final int char = _text.codeUnitAt(i);
      if (char == _backslash) {
        i += 2;
      } else if (char == _backtick) {
        i = _afterCodeSpan(_text, i, end);
      } else if (char == _exclamation && i + 1 < end && _text.codeUnitAt(i + 1) == _openBracket) {
        openers.add(_LinkOpener(bracketIndex: i + 1, spanStart: i, isImage: true));
        i += 2;
      } else if (char == _openBracket) {
        openers.add(_LinkOpener(bracketIndex: i, spanStart: i, isImage: false));
        i++;
      } else if (char == _closeBracket) {
        i = _closeBracketAt(openers, i, end);
      } else {
        i++;
      }
    }
  }

  int _closeBracketAt(List<_LinkOpener> openers, int closeBracket, int end) {
    if (openers.isEmpty) {
      return closeBracket + 1;
    }
    final _LinkOpener opener = openers.removeLast();
    if (!opener.isActive) {
      return closeBracket + 1;
    }
    final (TargetSpan destination, int linkEnd)? resolved = _resolveClosedBracket(
      opener,
      closeBracket,
      end,
    );
    if (resolved == null) {
      return closeBracket + 1;
    }
    final (TargetSpan destination, int linkEnd) = resolved;
    _matches.add((spanStart: opener.spanStart, spanEnd: linkEnd, destination: destination));
    if (!opener.isImage) {
      // CommonMark §6.5: links cannot contain other links.
      for (final earlier in openers) {
        if (!earlier.isImage) {
          earlier.isActive = false;
        }
      }
    }
    return linkEnd;
  }

  (TargetSpan, int)? _resolveClosedBracket(_LinkOpener opener, int closeBracket, int end) {
    final int afterClose = closeBracket + 1;
    if (afterClose < end && _text.codeUnitAt(afterClose) == _openParen) {
      final (TargetSpan, int)? inline = _parseInlineDestination(_text, afterClose + 1, end);
      if (inline != null) {
        return inline;
      }
    }
    if (_definitions.isEmpty) {
      return null;
    }
    return _resolveReferenceLink(opener.bracketIndex, closeBracket, end);
  }

  (TargetSpan, int)? _resolveReferenceLink(int openBracket, int closeBracket, int end) {
    final int afterClose = closeBracket + 1;
    if (afterClose < end && _text.codeUnitAt(afterClose) == _openBracket) {
      if (afterClose + 1 < end && _text.codeUnitAt(afterClose + 1) == _closeBracket) {
        // Collapsed reference link: `[label][]`.
        final TargetSpan? target = _lookupExactLabel(openBracket, closeBracket);
        return target == null ? null : (target, afterClose + 2);
      }
      if (_parseLinkLabel(_text, afterClose, end) case (
        final String refLabel,
        final int refClose,
      )) {
        // Full reference link: `[text][label]`. When `label` is undefined,
        // CommonMark forbids falling back to `[text]` as a shortcut link.
        final TargetSpan? target = _definitions[_normalizeLinkLabel(refLabel)];
        return target == null ? null : (target, refClose + 1);
      }
    }
    // Shortcut reference link: `[label]`.
    final TargetSpan? target = _lookupExactLabel(openBracket, closeBracket);
    return target == null ? null : (target, afterClose);
  }

  TargetSpan? _lookupExactLabel(int openBracket, int closeBracket) {
    if (_parseLinkLabel(_text, openBracket, closeBracket + 1) case (
      final String rawLabel,
      final int labelClose,
    ) when labelClose == closeBracket) {
      return _definitions[_normalizeLinkLabel(rawLabel)];
    }
    return null;
  }
}

/// Parses an inline destination and optional title in [text] starting at
/// [start] (right after `(`) within `[start, end)`.
(TargetSpan, int)? _parseInlineDestination(String text, int start, int end) {
  final int destStart = _skipSpaceAndSingleNewline(text, start, end);
  if (destStart >= end) {
    return null;
  }
  final (TargetSpan target, int afterTarget)? parsed = _parseTarget(text, destStart, end);
  if (parsed == null) {
    return null;
  }
  final (TargetSpan target, int afterTarget) = parsed;
  int closePos = _skipSpaceAndSingleNewline(text, afterTarget, end);
  if (closePos > afterTarget && closePos < end && text.codeUnitAt(closePos) != _closeParen) {
    final int? afterTitle = _parseTitle(text, closePos, end);
    if (afterTitle == null) {
      return null;
    }
    closePos = _skipSpaceAndSingleNewline(text, afterTitle, end);
  }
  if (closePos >= end || text.codeUnitAt(closePos) != _closeParen) {
    return null;
  }
  return (target, closePos + 1);
}

/// Parses an angle-bracketed (`<...>`) or bare link destination in [text] from
/// [start] within `[start, end)`.
///
/// Preserves raw backslash escapes in [TargetSpan]'s `target` so ignore
/// subjects match the text written in `SKILL.md` and Windows paths such as
/// `C:\_dir\file.md` or `\\server\share\file.md` keep their path separators.
(TargetSpan, int)? _parseTarget(String text, int start, int end) {
  if (start < end && text.codeUnitAt(start) == _lessThan) {
    final int targetStart = start + 1;
    final int? targetEnd = _angleTargetEnd(text, targetStart, end);
    if (targetEnd == null) {
      return null;
    }
    return (
      (
        targetStart: targetStart,
        targetEnd: targetEnd,
        target: text.substring(targetStart, targetEnd),
        isAngleBracketed: true,
      ),
      targetEnd + 1,
    );
  }
  final int? targetEnd = _bareTargetEnd(text, start, end);
  if (targetEnd == null) {
    return null;
  }
  return (
    (
      targetStart: start,
      targetEnd: targetEnd,
      target: text.substring(start, targetEnd),
      isAngleBracketed: false,
    ),
    targetEnd,
  );
}

int? _angleTargetEnd(String text, int start, int end) {
  var i = start;
  while (i < end) {
    final int char = text.codeUnitAt(i);
    if (char == _backslash) {
      if (i + 1 >= end) {
        return null;
      }
      final int next = text.codeUnitAt(i + 1);
      if (next == _newline || next == _carriageReturn) {
        return null;
      }
      i += 2;
    } else if (char == _greaterThan) {
      return i;
    } else if (char == _lessThan || char == _newline || char == _carriageReturn) {
      return null;
    } else {
      i++;
    }
  }
  return null;
}

int? _bareTargetEnd(String text, int start, int end) {
  var i = start;
  var parenDepth = 0;
  while (i < end) {
    final int char = text.codeUnitAt(i);
    if (char == _backslash && i + 1 < end && _isAsciiPunctuation(text.codeUnitAt(i + 1))) {
      i += 2;
      continue;
    }
    if (char <= _space || char == _delete || (char == _closeParen && parenDepth == 0)) {
      break;
    }
    if (char == _openParen) {
      parenDepth++;
    } else if (char == _closeParen) {
      parenDepth--;
    }
    i++;
  }
  return parenDepth == 0 ? i : null;
}

int? _parseTitle(String text, int start, int end) {
  if (start >= end) {
    return null;
  }
  final int open = text.codeUnitAt(start);
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
    final int char = text.codeUnitAt(i);
    if (char == _backslash) {
      if (i + 1 >= end) {
        return null;
      }
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

/// Parses `[label]` in [text] starting at [openBracket] within
/// `[openBracket, end)`, returning the raw label text and closing `]` index.
(String, int)? _parseLinkLabel(String text, int openBracket, int end) {
  if (openBracket >= end || text.codeUnitAt(openBracket) != _openBracket) {
    return null;
  }
  final int labelStart = openBracket + 1;
  final int maxEnd = (labelStart + _maxLinkLabelLength + 1).clamp(0, end);
  var i = labelStart;
  var hasNonWhitespace = false;
  while (i < maxEnd) {
    final int char = text.codeUnitAt(i);
    if (char == _closeBracket) {
      return hasNonWhitespace ? (text.substring(labelStart, i), i) : null;
    }
    if (char == _openBracket || (char == _backslash && i + 1 >= end)) {
      return null;
    }
    if (char == _backslash) {
      hasNonWhitespace = true;
      i += 2;
    } else {
      hasNonWhitespace = hasNonWhitespace || !_isAsciiWhitespace(char);
      i++;
    }
  }
  return null;
}

String _normalizeLinkLabel(String rawLabel) => rawLabel
    .replaceAll(_edgeAsciiWhitespacePattern, '')
    .replaceAll(_labelWhitespacePattern, ' ')
    .toLowerCase()
    .replaceAll('ß', 'ss');

int _afterCodeSpan(String text, int start, int end) {
  final int openEnd = runEnd(text, start, end, _backtick);
  final int length = openEnd - start;
  var i = openEnd;
  while (i < end) {
    final int close = text.indexOf('`', i);
    if (close == -1 || close >= end) {
      break;
    }
    final int closeEnd = runEnd(text, close, end, _backtick);
    if (closeEnd - close == length) {
      return closeEnd;
    }
    i = closeEnd;
  }
  return openEnd;
}

int _skipSpaceAndSingleNewline(String text, int start, int end) {
  var i = start;
  var newlines = 0;
  while (i < end) {
    final int char = text.codeUnitAt(i);
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

int? _skipDefinitionSpace(
  String text,
  int start,
  int end, {
  required List<ContainerMarker> containers,
}) {
  final int afterHorizontal = skipHorizontalSpace(text, start, end);
  if (!_isAtLineEnd(text, afterHorizontal, end)) {
    return afterHorizontal;
  }
  final int nextLine = _afterLineEnding(text, afterHorizontal, end);
  if (nextLine >= end) {
    return nextLine;
  }
  final int lineEnd = _contentEndOfLine(text, nextLine, end);
  final (int matched, _, int afterContainers) = matchContainers(
    text,
    nextLine,
    lineEnd,
    containers,
  );
  if (!onlyListContainersRemain(containers, matched)) {
    return null;
  }
  return skipHorizontalSpace(text, afterContainers, end);
}

int _contentEndOfLine(String text, int lineStart, int blockEnd) {
  final int newline = text.indexOf('\n', lineStart);
  final int rawEnd = newline == -1 || newline >= blockEnd ? blockEnd : newline + 1;
  return stripLineEnding(text, lineStart, rawEnd);
}

bool _isAtLineEnd(String text, int pos, int end) {
  if (pos >= end) {
    return true;
  }
  final int char = text.codeUnitAt(pos);
  return char == _newline ||
      (char == _carriageReturn && pos + 1 < end && text.codeUnitAt(pos + 1) == _newline);
}

int _afterLineEnding(String text, int pos, int end) {
  if (pos >= end) {
    return end;
  }
  var i = pos;
  if (text.codeUnitAt(i) == _carriageReturn) {
    i++;
  }
  if (i < end && text.codeUnitAt(i) == _newline) {
    i++;
  }
  return i;
}

bool _isAsciiWhitespace(int char) =>
    char == _space || char == _tab || char == _newline || char == _carriageReturn;

/// CommonMark §2.4 ASCII punctuation characters (`0x21..0x2F`, `0x3A..0x40`,
/// `0x5B..0x60`, `0x7B..0x7E`).
bool _isAsciiPunctuation(int char) =>
    (char >= _exclamation && char <= 0x2F) ||
    (char >= _colon && char <= 0x40) ||
    (char >= _openBracket && char <= _backtick) ||
    (char >= 0x7B && char <= _tilde);
