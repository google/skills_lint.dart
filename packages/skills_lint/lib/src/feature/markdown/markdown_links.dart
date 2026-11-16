// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Finds the links in Markdown and rewrites their destinations in place.
///
/// The scanners follow CommonMark (https://spec.commonmark.org/0.31.2/), the
/// Markdown specification that GitHub and most Markdown renderers implement.
/// Following it means `skills_lint` reads a link wherever a renderer shows
/// one, and nowhere else: not in code, and not in text that only looks like a
/// link. Comments link to the section of the specification that each rule
/// comes from.
///
/// The scan has two passes, as CommonMark's does:
///
/// 1. `block_scanner.dart` splits the document into paragraphs and headings,
///    skipping code blocks and stepping past blockquote and list markers.
/// 2. `inline_scanner.dart` reads link reference definitions at the start of
///    each block, then the links and images in each block.
///
/// `package:markdown` is not used, because its syntax tree has no source
/// offsets, drops link reference definitions, and percent-encodes and
/// unescapes destinations, while the rules need each destination's exact text
/// and offsets to report it and to rewrite it.
library;

import 'package:source_span/source_span.dart';

import 'block_scanner.dart';
import 'inline_scanner.dart';
import 'link_models.dart';

export 'link_models.dart' show LinkDestination, MarkdownLink;

/// The links and images in [markdown], from offset [start], in document
/// order.
///
/// Inline links (`[text](destination)`) and reference links (`[text][label]`,
/// `[label][]` and `[label]`, resolved against `[label]: destination`
/// definitions) are found. Link syntax in code spans and code blocks is not a
/// link, and is skipped.
List<MarkdownLink> markdownLinksIn(String markdown, {int start = 0}) {
  if (start >= markdown.length) {
    return const [];
  }
  final file = SourceFile.fromString(markdown);
  final MarkdownBlocks blocks = scanMarkdownBlocks(file, start: start);
  final scanner = MarkdownInlineScanner(file, blocks.text);

  // A definition can come after the links that use it, so read every
  // definition before any link.
  final definitions = <String, LinkDestination>{};
  final inlineSpans = <FileSpan>[];
  for (final FileSpan block in blocks.blocks) {
    // Definitions can only start a block (CommonMark §4.7).
    int inlineStart = block.start.offset;
    for (
      LinkDefinition? definition = scanner.parseDefinition(inlineStart, block.end.offset);
      definition != null;
      definition = scanner.parseDefinition(inlineStart, block.end.offset)
    ) {
      // The first definition of a label wins.
      definitions.putIfAbsent(definition.label, () => definition!.destination);
      inlineStart = definition.end;
    }
    if (inlineStart < block.end.offset) {
      inlineSpans.add(file.span(inlineStart, block.end.offset));
    }
  }
  return [
    for (final FileSpan span in inlineSpans)
      ...scanner.scanLinks(span.start.offset, span.end.offset, definitions),
  ];
}

/// [markdown] with each destination in [replacements] replaced by its value.
///
/// Destinations are replaced from last to first in the source, so earlier
/// offsets stay valid. A replacement that holds whitespace or parentheses is
/// enclosed in `<` and `>`, unless the destination already is, so it stays a
/// single destination and file names stay readable as written.
///
/// Several reference links that use one `[label]: destination` definition
/// share one [LinkDestination], so the definition is rewritten once.
String replaceLinkDestinations(String markdown, Map<LinkDestination, String> replacements) {
  final List<LinkDestination> ordered = replacements.keys.toList()
    ..sort((a, b) => b.span.start.offset.compareTo(a.span.start.offset));
  var result = markdown;
  for (final destination in ordered) {
    final String replacement = replacements[destination]!;
    final bool enclose = !destination.isAngleBracketed && _needsAngleBrackets(replacement);
    result = result.replaceRange(
      destination.span.start.offset,
      destination.span.end.offset,
      enclose ? '<$replacement>' : replacement,
    );
  }
  return result;
}

bool _needsAngleBrackets(String destination) =>
    destination.contains(' ') ||
    destination.contains('\t') ||
    destination.contains('\n') ||
    destination.contains('(') ||
    destination.contains(')');
