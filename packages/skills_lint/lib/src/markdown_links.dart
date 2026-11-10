// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:meta/meta.dart';

import 'models/source_region.dart';

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

/// Maximum characters allowed inside a CommonMark link label (`[...]`).
const int _maxLinkLabelLength = 999;

/// First non-whitespace characters that can introduce an ATX heading, thematic
/// break, setext heading underline, list item, or code fence.
final Set<int> _blockMarkerChars = {...'#-=+*_`~0123456789'.codeUnits};

final RegExp _atxHeadingPattern = RegExp(r'^#{1,6}(?:[ \t]|$)');
final RegExp _thematicBreakPattern = RegExp(
  r'^(?:-[ \t]*){3,}$|^(?:\*[ \t]*){3,}$|^(?:_[ \t]*){3,}$',
);
final RegExp _setextUnderlinePattern = RegExp(r'^(?:=+|-+)[ \t]*$');
final RegExp _listMarkerPattern = RegExp(r'^(?:[-+*]|\d{1,9}[.)])(?:[ \t]|$)');
final RegExp _labelWhitespacePattern = RegExp(r'[ \t\r\n]+');
final RegExp _unsafeBareDestinationChars = RegExp(r'[\s()]');

/// A Markdown link or image resolved from a document, with its 1-based [region].
@immutable
class MarkdownLink {
  const MarkdownLink({required this.target, required this.region});

  /// Link destination as written, without enclosing `<` and `>` or a title.
  final String target;

  /// 1-based line and column span of the link in the source file, where line 1
  /// and column 1 mark the start of the file and [SourceRegion.endColumn] is
  /// 1-based exclusive (matching SARIF 2.1.0 §3.30).
  final SourceRegion region;
}

/// Links and images resolved from [markdown], in document order.
///
/// Follows CommonMark for path validation: skips code spans and fenced or
/// indented code blocks (because CommonMark treats code as literal text and
/// skills include illustrative or intentionally invalid link examples in code),
/// reads `<...>` and parenthesized inline destinations, and resolves full
/// (`[text][ref]`), collapsed (`[ref][]`), and shortcut (`[ref]`) reference
/// links against `[ref]:` definitions.
///
/// [startLine] is the 1-based line number in the enclosing file where
/// [markdown] begins (defaults to `1`, the first line of the file).
List<MarkdownLink> markdownLinksIn(String markdown, {int startLine = 1}) {
  if (markdown.isEmpty) {
    return const [];
  }
  final _ScanResult scan = _scanMarkdown(markdown);
  return [
    for (final _LinkMatch match in scan.matches)
      MarkdownLink(
        target: match.destination.target,
        region: scan.lineIndex.regionFor(match.spanStart, match.spanEnd, baseLine: startLine),
      ),
  ];
}

/// Rewrites each referenced link destination in [markdown] when [rewrite]
/// produces a non-null replacement for that destination.
///
/// Encloses a replacement containing whitespace or parentheses in `<` and `>`
/// (rather than percent-encoding spaces) when the destination is not already
/// enclosed in `<` and `>`, keeping filenames readable as written. When one or
/// more reference-style links resolve to a `[ref]:` definition, rewrites that
/// definition's destination once in place.
String replaceMarkdownLinkTargets(String markdown, String? Function(String target) rewrite) {
  if (markdown.isEmpty) {
    return markdown;
  }
  final _ScanResult scan = _scanMarkdown(markdown);
  if (scan.matches.isEmpty) {
    return markdown;
  }
  // Deduplicate shared `[ref]:` definitions by targetStart and sort in
  // ascending source order, because a `[ref]:` definition can sit either above
  // or below inline links that precede or follow its reference sites.
  final spansByStart = <int, _TargetSpan>{
    for (final _LinkMatch match in scan.matches) match.destination.targetStart: match.destination,
  };
  final List<_TargetSpan> orderedSpans = spansByStart.values.toList()
    ..sort((a, b) => a.targetStart.compareTo(b.targetStart));

  final buffer = StringBuffer();
  var copiedUpTo = 0;
  for (final span in orderedSpans) {
    final String? replacement = rewrite(span.target);
    if (replacement == null) {
      continue;
    }
    final bool wrapInAngleBrackets =
        !span.isAngleBracketed && _unsafeBareDestinationChars.hasMatch(replacement);
    buffer
      ..write(markdown.substring(copiedUpTo, span.targetStart))
      ..write(wrapInAngleBrackets ? '<$replacement>' : replacement);
    copiedUpTo = span.targetEnd;
  }
  if (copiedUpTo == 0) {
    return markdown;
  }
  buffer.write(markdown.substring(copiedUpTo));
  return buffer.toString();
}

_ScanResult _scanMarkdown(String markdown) {
  final (List<_TextBlock> blocks, _LineIndex lineIndex) = _BlockScanner(markdown).scan();
  final definitions = <String, _TargetSpan>{};
  final inlineRanges = <(int, int)>[];

  for (final block in blocks) {
    final int inlineStart = block.allowsDefinitions
        ? _consumeDefinitions(markdown, block, definitions)
        : block.start;
    if (inlineStart < block.end) {
      inlineRanges.add((inlineStart, block.end));
    }
  }

  final matches = <_LinkMatch>[];
  final scanner = _InlineScanner(markdown, definitions, matches);
  for (final (int start, int end) in inlineRanges) {
    scanner.scanRange(start, end);
  }
  return _ScanResult(matches: matches, lineIndex: lineIndex);
}

class _ScanResult {
  const _ScanResult({required this.matches, required this.lineIndex});

  final List<_LinkMatch> matches;
  final _LineIndex lineIndex;
}

class _TargetSpan {
  const _TargetSpan({
    required this.targetStart,
    required this.targetEnd,
    required this.target,
    required this.isAngleBracketed,
  });

  final int targetStart;
  final int targetEnd;
  final String target;
  final bool isAngleBracketed;
}

class _LinkMatch {
  const _LinkMatch({required this.spanStart, required this.spanEnd, required this.destination});

  final int spanStart;
  final int spanEnd;
  final _TargetSpan destination;
}

class _TextBlock {
  const _TextBlock({
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

class _LineIndex {
  const _LineIndex(this._lineStarts);

  final List<int> _lineStarts;

  SourceRegion regionFor(int startOffset, int endOffset, {required int baseLine}) {
    final (int startLine, int startColumn) = _locationAt(startOffset, baseLine: baseLine);
    final (int endLine, int endColumn) = _locationAt(endOffset, baseLine: baseLine);
    return SourceRegion(
      startLine: startLine,
      startColumn: startColumn,
      endLine: endLine,
      endColumn: endColumn,
    );
  }

  (int line, int column) _locationAt(int offset, {required int baseLine}) {
    var low = 0;
    int high = _lineStarts.length - 1;
    while (low < high) {
      final int mid = (low + high + 1) >> 1;
      if (_lineStarts[mid] <= offset) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    final int lineStart = _lineStarts.isEmpty ? 0 : _lineStarts[low];
    return (baseLine + low, offset - lineStart + 1);
  }
}

/// Splits Markdown into non-code text blocks (paragraphs and ATX headings) and
/// records the starting offset of every line.
class _BlockScanner {
  _BlockScanner(this._markdown);

  final String _markdown;
  final List<_TextBlock> _blocks = [];
  final List<int> _lineStarts = [];

  _OpenFence? _openFence;
  int? _listContentIndent;
  bool _afterBlankLine = true;
  int? _paragraphStart;
  int _paragraphQuoteDepth = 0;
  int _paragraphMaxDefIndent = 3;

  (List<_TextBlock>, _LineIndex) scan() {
    var lineStart = 0;
    while (lineStart < _markdown.length) {
      _lineStarts.add(lineStart);
      final int newline = _markdown.indexOf('\n', lineStart);
      final int lineEnd = newline == -1 ? _markdown.length : newline + 1;
      _processLine(lineStart, lineEnd);
      lineStart = lineEnd;
    }
    _flushParagraph(_markdown.length);
    return (_blocks, _LineIndex(_lineStarts));
  }

  void _processLine(int lineStart, int lineEnd) {
    final int contentEnd = _stripLineEnding(_markdown, lineStart, lineEnd);
    if (_consumeOpenFenceLine(lineStart, contentEnd)) {
      return;
    }

    final (int quoteDepth, int unquotedStart) = _stripQuoteMarkers(
      _markdown,
      lineStart,
      contentEnd,
    );
    if (_paragraphStart != null && quoteDepth > _paragraphQuoteDepth) {
      _flushParagraph(lineStart);
    }

    final (int indent, int nonSpaceStart) = _leadingIndent(_markdown, unquotedStart, contentEnd);
    if (nonSpaceStart == contentEnd) {
      _flushParagraph(lineStart);
      _afterBlankLine = true;
      return;
    }

    final bool startsMarker = _blockMarkerChars.contains(_markdown.codeUnitAt(nonSpaceStart));
    if (_afterBlankLine &&
        _listContentIndent != null &&
        indent < _listContentIndent! &&
        !(indent <= 3 && startsMarker && _matchesListMarker(nonSpaceStart, contentEnd))) {
      _listContentIndent = null;
    }

    final int baseIndent = _listContentIndent ?? 0;
    if (_handleBlockStructure(
      lineStart: lineStart,
      lineEnd: lineEnd,
      contentEnd: contentEnd,
      quoteDepth: quoteDepth,
      indent: indent,
      baseIndent: baseIndent,
      nonSpaceStart: nonSpaceStart,
      startsMarker: startsMarker,
    )) {
      return;
    }

    if (_paragraphStart == null) {
      _paragraphStart = lineStart;
      _paragraphQuoteDepth = quoteDepth;
      _paragraphMaxDefIndent = baseIndent + 3;
    }
    _afterBlankLine = false;
  }

  bool _consumeOpenFenceLine(int lineStart, int contentEnd) {
    final _OpenFence? fence = _openFence;
    if (fence == null) {
      return false;
    }
    final (int quoteDepth, int unquotedStart) = _stripQuoteMarkers(
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
    final (int indent, int nonSpaceStart) = _leadingIndent(_markdown, unquotedStart, contentEnd);
    final int baseIndent = _listContentIndent ?? 0;
    if (indent <= baseIndent + 3 && _isClosingFence(_markdown, nonSpaceStart, contentEnd, fence)) {
      _openFence = null;
    }
    return true;
  }

  bool _handleBlockStructure({
    required int lineStart,
    required int lineEnd,
    required int contentEnd,
    required int quoteDepth,
    required int indent,
    required int baseIndent,
    required int nonSpaceStart,
    required bool startsMarker,
  }) {
    if (indent <= baseIndent + 3 && startsMarker) {
      final _OpenFence? opened = _tryOpenFence(_markdown, nonSpaceStart, contentEnd, quoteDepth);
      if (opened != null) {
        _flushParagraph(lineStart);
        _openFence = opened;
        _afterBlankLine = false;
        return true;
      }
    }

    if (_paragraphStart == null && indent >= baseIndent + 4) {
      _afterBlankLine = false;
      return true;
    }

    if (!startsMarker || indent > baseIndent + 3) {
      return false;
    }

    final String trimmedRight = _markdown.substring(nonSpaceStart, contentEnd);
    if ((_paragraphStart != null && _setextUnderlinePattern.hasMatch(trimmedRight)) ||
        _thematicBreakPattern.hasMatch(trimmedRight)) {
      _flushParagraph(lineStart);
      _afterBlankLine = false;
      return true;
    }

    if (_atxHeadingPattern.hasMatch(trimmedRight)) {
      _flushParagraph(lineStart);
      _blocks.add(
        _TextBlock(
          start: nonSpaceStart,
          end: lineEnd,
          quoteDepth: quoteDepth,
          maxDefinitionIndent: 0,
          allowsDefinitions: false,
        ),
      );
      _afterBlankLine = false;
      return true;
    }

    final RegExpMatch? listMatch = _listMarkerPattern.firstMatch(trimmedRight);
    if (listMatch != null) {
      _startListItem(
        lineStart: lineStart,
        contentEnd: contentEnd,
        quoteDepth: quoteDepth,
        indent: indent,
        nonSpaceStart: nonSpaceStart,
        markerLength: listMatch.end,
      );
      return true;
    }

    return false;
  }

  void _startListItem({
    required int lineStart,
    required int contentEnd,
    required int quoteDepth,
    required int indent,
    required int nonSpaceStart,
    required int markerLength,
  }) {
    _flushParagraph(lineStart);
    final int markerEnd = nonSpaceStart + markerLength;
    final (int postMarkerIndent, int itemTextStart) = _leadingIndent(
      _markdown,
      markerEnd,
      contentEnd,
    );
    final int markerColumns = indent + markerLength;
    final int listIndent = itemTextStart == contentEnd || postMarkerIndent >= 4
        ? markerColumns
        : markerColumns + postMarkerIndent;
    _listContentIndent = listIndent;
    if (itemTextStart < contentEnd) {
      _paragraphStart = itemTextStart;
      _paragraphQuoteDepth = quoteDepth;
      _paragraphMaxDefIndent = listIndent + 3;
    }
    _afterBlankLine = false;
  }

  bool _matchesListMarker(int nonSpaceStart, int contentEnd) {
    final String rest = _markdown.substring(nonSpaceStart, contentEnd);
    return !_thematicBreakPattern.hasMatch(rest) && _listMarkerPattern.hasMatch(rest);
  }

  void _flushParagraph(int end) {
    final int? start = _paragraphStart;
    if (start != null && start < end) {
      _blocks.add(
        _TextBlock(
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
  final int runEnd = _runEnd(text, start, end, first);
  final int length = runEnd - start;
  if (length < 3) {
    return null;
  }
  if (first == _backtick && text.substring(runEnd, end).contains('`')) {
    return null;
  }
  return _OpenFence(markerChar: first, minLength: length, quoteDepth: quoteDepth);
}

bool _isClosingFence(String text, int start, int end, _OpenFence fence) {
  if (start >= end || text.codeUnitAt(start) != fence.markerChar) {
    return false;
  }
  final int runEnd = _runEnd(text, start, end, fence.markerChar);
  if (runEnd - start < fence.minLength) {
    return false;
  }
  return _skipHorizontalSpace(text, runEnd, end) == end;
}

/// Consumes leading CommonMark link reference definitions (`[ref]: target`) at
/// the start of [block], recording the first definition for each normalized
/// label in [definitions] and returning the offset where paragraph inline text
/// resumes.
int _consumeDefinitions(String text, _TextBlock block, Map<String, _TargetSpan> definitions) {
  int pos = block.start;
  while (pos < block.end) {
    final (String label, _TargetSpan target, int nextPos)? parsed = _parseDefinition(
      text,
      pos,
      block.end,
      quoteDepth: block.quoteDepth,
      maxIndent: block.maxDefinitionIndent,
    );
    if (parsed == null) {
      break;
    }
    final (String label, _TargetSpan target, int nextPos) = parsed;
    definitions.putIfAbsent(label, () => target);
    pos = nextPos;
  }
  return pos;
}

(String, _TargetSpan, int)? _parseDefinition(
  String text,
  int start,
  int blockEnd, {
  required int quoteDepth,
  required int maxIndent,
}) {
  final int? labelOpen = _definitionLabelStart(
    text,
    start,
    blockEnd,
    quoteDepth: quoteDepth,
    maxIndent: maxIndent,
  );
  if (labelOpen == null) {
    return null;
  }

  final (String rawLabel, int labelClose)? label = _parseLinkLabel(text, labelOpen, blockEnd);
  if (label == null) {
    return null;
  }
  final int colonIndex = label.$2 + 1;
  if (colonIndex >= blockEnd || text.codeUnitAt(colonIndex) != _colon) {
    return null;
  }

  final int? destStart = _skipDefinitionSpace(
    text,
    colonIndex + 1,
    blockEnd,
    quoteDepth: quoteDepth,
  );
  if (destStart == null || destStart >= blockEnd) {
    return null;
  }

  final (_TargetSpan target, int afterTarget)? parsedTarget = _parseTarget(
    text,
    destStart,
    blockEnd,
  );
  if (parsedTarget == null) {
    return null;
  }
  final (_TargetSpan target, int afterTarget) = parsedTarget;
  if (!target.isAngleBracketed && target.target.isEmpty) {
    return null;
  }

  final int? defEnd = _parseDefinitionTail(text, afterTarget, blockEnd, quoteDepth: quoteDepth);
  if (defEnd == null) {
    return null;
  }
  return (_normalizeLinkLabel(label.$1), target, defEnd);
}

int? _definitionLabelStart(
  String text,
  int start,
  int blockEnd, {
  required int quoteDepth,
  required int maxIndent,
}) {
  final bool atLineStart = start == 0 || text.codeUnitAt(start - 1) == _newline;
  if (!atLineStart) {
    final (int indent, int pos) = _leadingIndent(text, start, blockEnd);
    return indent <= 3 && pos < blockEnd && text.codeUnitAt(pos) == _openBracket ? pos : null;
  }
  final (int quotes, int unquoted) = _stripQuoteMarkers(
    text,
    start,
    blockEnd,
    maxQuotes: quoteDepth,
  );
  if (quotes < quoteDepth) {
    return null;
  }
  final (int indent, int pos) = _leadingIndent(text, unquoted, blockEnd);
  return indent <= maxIndent && pos < blockEnd && text.codeUnitAt(pos) == _openBracket ? pos : null;
}

int? _parseDefinitionTail(String text, int afterTarget, int blockEnd, {required int quoteDepth}) {
  final int afterSpaces = _skipHorizontalSpace(text, afterTarget, blockEnd);
  if (_isAtLineEnd(text, afterSpaces, blockEnd)) {
    final int destLineEnd = _afterLineEnding(text, afterSpaces, blockEnd);
    final int? nextLineTitleEnd = _tryTitleOnNextLine(
      text,
      destLineEnd,
      blockEnd,
      quoteDepth: quoteDepth,
    );
    return nextLineTitleEnd ?? destLineEnd;
  }
  if (afterSpaces == afterTarget) {
    return null;
  }
  final int? afterTitle = _parseTitle(text, afterSpaces, blockEnd);
  if (afterTitle == null) {
    return null;
  }
  final int afterTitleSpaces = _skipHorizontalSpace(text, afterTitle, blockEnd);
  if (!_isAtLineEnd(text, afterTitleSpaces, blockEnd)) {
    return null;
  }
  return _afterLineEnding(text, afterTitleSpaces, blockEnd);
}

int? _tryTitleOnNextLine(String text, int lineStart, int blockEnd, {required int quoteDepth}) {
  if (lineStart >= blockEnd) {
    return null;
  }
  final (int quotes, int unquoted) = _stripQuoteMarkers(
    text,
    lineStart,
    blockEnd,
    maxQuotes: quoteDepth,
  );
  if (quotes < quoteDepth) {
    return null;
  }
  final int titleStart = _skipHorizontalSpace(text, unquoted, blockEnd);
  final int? afterTitle = _parseTitle(text, titleStart, blockEnd);
  if (afterTitle == null) {
    return null;
  }
  final int afterTitleSpaces = _skipHorizontalSpace(text, afterTitle, blockEnd);
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
class _InlineScanner {
  _InlineScanner(this._text, this._definitions, this._matches);

  final String _text;
  final Map<String, _TargetSpan> _definitions;
  final List<_LinkMatch> _matches;

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
    final (_TargetSpan destination, int linkEnd)? resolved = _resolveClosedBracket(
      opener,
      closeBracket,
      end,
    );
    if (resolved == null) {
      return closeBracket + 1;
    }
    final (_TargetSpan destination, int linkEnd) = resolved;
    _matches.add(
      _LinkMatch(spanStart: opener.spanStart, spanEnd: linkEnd, destination: destination),
    );
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

  (_TargetSpan, int)? _resolveClosedBracket(_LinkOpener opener, int closeBracket, int end) {
    final int afterClose = closeBracket + 1;
    if (afterClose < end && _text.codeUnitAt(afterClose) == _openParen) {
      final (_TargetSpan, int)? inline = _parseInlineDestination(_text, afterClose + 1, end);
      if (inline != null) {
        return inline;
      }
    }
    if (_definitions.isEmpty) {
      return null;
    }
    return _resolveReferenceLink(opener.bracketIndex, closeBracket, end);
  }

  (_TargetSpan, int)? _resolveReferenceLink(int openBracket, int closeBracket, int end) {
    final int afterClose = closeBracket + 1;
    if (afterClose < end && _text.codeUnitAt(afterClose) == _openBracket) {
      if (afterClose + 1 < end && _text.codeUnitAt(afterClose + 1) == _closeBracket) {
        // Collapsed reference link: `[label][]`.
        final _TargetSpan? target = _lookupExactLabel(openBracket, closeBracket);
        return target == null ? null : (target, afterClose + 2);
      }
      final (String refLabel, int refClose)? fullLabel = _parseLinkLabel(_text, afterClose, end);
      if (fullLabel != null) {
        // Full reference link: `[text][label]`. When `label` is undefined,
        // CommonMark forbids falling back to `[text]` as a shortcut link.
        final _TargetSpan? target = _definitions[_normalizeLinkLabel(fullLabel.$1)];
        return target == null ? null : (target, fullLabel.$2 + 1);
      }
    }
    // Shortcut reference link: `[label]`.
    final _TargetSpan? target = _lookupExactLabel(openBracket, closeBracket);
    return target == null ? null : (target, afterClose);
  }

  _TargetSpan? _lookupExactLabel(int openBracket, int closeBracket) {
    final (String rawLabel, int labelClose)? parsed = _parseLinkLabel(
      _text,
      openBracket,
      closeBracket + 1,
    );
    if (parsed == null || parsed.$2 != closeBracket) {
      return null;
    }
    return _definitions[_normalizeLinkLabel(parsed.$1)];
  }
}

/// Parses an inline destination and optional title starting right after `(`,
/// returning the destination span and the offset immediately after `)`.
(_TargetSpan, int)? _parseInlineDestination(String text, int start, int end) {
  final int destStart = _skipSpaceAndSingleNewline(text, start, end);
  if (destStart >= end) {
    return null;
  }
  final (_TargetSpan target, int afterTarget)? parsed = _parseTarget(text, destStart, end);
  if (parsed == null) {
    return null;
  }
  final (_TargetSpan target, int afterTarget) = parsed;
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

/// Parses an angle-bracketed (`<...>`) or bare link destination at [start],
/// returning its [_TargetSpan] and the offset right after the destination
/// (past `>` when angle-bracketed).
(_TargetSpan, int)? _parseTarget(String text, int start, int end) {
  if (start < end && text.codeUnitAt(start) == _lessThan) {
    final int targetStart = start + 1;
    final int? targetEnd = _angleTargetEnd(text, targetStart, end);
    if (targetEnd == null) {
      return null;
    }
    return (
      _TargetSpan(
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
    _TargetSpan(
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
    if (char == _backslash && i + 1 < end) {
      i += 2;
      continue;
    }
    if (char <= _space || (char == _closeParen && parenDepth == 0)) {
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

/// Parses `[label]` starting at `[` (`openBracket`), returning the raw label
/// content and the index of the closing `]`.
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

String _normalizeLinkLabel(String rawLabel) =>
    rawLabel.trim().replaceAll(_labelWhitespacePattern, ' ').toLowerCase().replaceAll('ß', 'ss');

int _afterCodeSpan(String text, int start, int end) {
  final int runEnd = _runEnd(text, start, end, _backtick);
  final int length = runEnd - start;
  var i = runEnd;
  while (i < end) {
    final int close = text.indexOf('`', i);
    if (close == -1 || close >= end) {
      break;
    }
    final int closeEnd = _runEnd(text, close, end, _backtick);
    if (closeEnd - close == length) {
      return closeEnd;
    }
    i = closeEnd;
  }
  return runEnd;
}

int _runEnd(String text, int start, int end, int char) {
  var i = start;
  while (i < end && text.codeUnitAt(i) == char) {
    i++;
  }
  return i;
}

(int, int) _leadingIndent(String text, int start, int end) {
  var columns = 0;
  var i = start;
  while (i < end) {
    final int char = text.codeUnitAt(i);
    if (char == _space) {
      columns++;
    } else if (char == _tab) {
      columns += 4 - (columns % 4);
    } else {
      break;
    }
    i++;
  }
  return (columns, i);
}

(int, int) _stripQuoteMarkers(String text, int start, int end, {int? maxQuotes}) {
  var depth = 0;
  var pos = start;
  while (maxQuotes == null || depth < maxQuotes) {
    final (int indent, int markerPos) = _leadingIndent(text, pos, end);
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

int _stripLineEnding(String text, int start, int end) {
  var contentEnd = end;
  if (contentEnd > start && text.codeUnitAt(contentEnd - 1) == _newline) {
    contentEnd--;
  }
  if (contentEnd > start && text.codeUnitAt(contentEnd - 1) == _carriageReturn) {
    contentEnd--;
  }
  return contentEnd;
}

int _skipHorizontalSpace(String text, int start, int end) {
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

int? _skipDefinitionSpace(String text, int start, int end, {required int quoteDepth}) {
  final int afterHorizontal = _skipHorizontalSpace(text, start, end);
  if (!_isAtLineEnd(text, afterHorizontal, end)) {
    return afterHorizontal;
  }
  final int nextLine = _afterLineEnding(text, afterHorizontal, end);
  if (nextLine >= end) {
    return nextLine;
  }
  final (int quotes, int unquoted) = _stripQuoteMarkers(text, nextLine, end, maxQuotes: quoteDepth);
  if (quotes < quoteDepth) {
    return null;
  }
  return _skipHorizontalSpace(text, unquoted, end);
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
