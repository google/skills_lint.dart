// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// CommonMark link and image extraction and in-place destination rewriting.
///
/// `skills_lint` scans CommonMark directly rather than delegating to
/// `package:markdown` because `package:markdown` strips line endings, blockquote
/// markers, and list indentation before inline parsing and emits AST `Element`
/// nodes without source offsets, omits `[ref]:` definition spans from the AST
/// (preventing in-place `--fix` rewrites), and percent-encodes spaces while
/// stripping backslashes before ASCII punctuation (altering rule ignore
/// subjects and Windows paths).
library;

import 'package:meta/meta.dart';

import 'markdown_block_scanner.dart';
import 'markdown_inline_scanner.dart';
import 'models/source_region.dart';

final RegExp _unsafeBareDestinationChars = RegExp(r'[\s()]');

/// A Markdown link or image resolved from a document, with its 1-based [region].
@immutable
class MarkdownLink {
  const MarkdownLink({required this.target, required this.region});

  /// Link destination as written, without enclosing `<` and `>` or a title.
  final String target;

  /// 1-based line and column span of the link in the source file.
  ///
  /// Line 1 and column 1 mark the start of the file, and
  /// [SourceRegion.endColumn] is 1-based exclusive (matching SARIF 2.1.0 §3.30).
  final SourceRegion region;
}

/// Links and images resolved from [markdown], in document order.
///
/// Follows CommonMark for path validation: skips code spans and fenced code
/// blocks (because CommonMark treats code as literal text and skills include
/// illustrative or intentionally invalid link examples in code),
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
  final (List<LinkMatch> matches, _LineIndex lineIndex) = _scanMarkdown(markdown);
  return [
    for (final LinkMatch match in matches)
      MarkdownLink(
        target: match.destination.target,
        region: lineIndex.regionFor(match.spanStart, match.spanEnd, baseLine: startLine),
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
  final (List<LinkMatch> matches, _) = _scanMarkdown(markdown);
  if (matches.isEmpty) {
    return markdown;
  }
  // Deduplicate shared `[ref]:` definitions by targetStart and sort in
  // ascending source order, because a `[ref]:` definition can sit either above
  // or below inline links that precede or follow its reference sites.
  final spansByStart = <int, TargetSpan>{
    for (final LinkMatch match in matches) match.destination.targetStart: match.destination,
  };
  final List<TargetSpan> orderedSpans = spansByStart.values.toList()
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

(List<LinkMatch>, _LineIndex) _scanMarkdown(String markdown) {
  final MarkdownBlocks scanned = scanMarkdownBlocks(markdown);
  final String text = scanned.text;
  final definitions = <String, TargetSpan>{};
  final inlineRanges = <(int, int)>[];
  for (final (int blockStart, int blockEnd) in scanned.blocks) {
    // Definitions open a block, before its inline text (CommonMark §4.7).
    var inlineStart = blockStart;
    while (true) {
      if (parseDefinition(text, inlineStart, blockEnd) case (
        final String label,
        final TargetSpan target,
        final int definitionEnd,
      )) {
        definitions.putIfAbsent(label, () => target);
        inlineStart = definitionEnd;
      } else {
        break;
      }
    }
    if (inlineStart < blockEnd) {
      inlineRanges.add((inlineStart, blockEnd));
    }
  }

  final matches = <LinkMatch>[];
  final scanner = MarkdownInlineScanner(text, definitions, matches);
  for (final (int start, int end) in inlineRanges) {
    scanner.scanRange(start, end);
  }
  return (matches, _LineIndex(scanned.lineStarts));
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
