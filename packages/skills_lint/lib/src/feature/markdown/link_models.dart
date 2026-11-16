// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:meta/meta.dart';
import 'package:source_span/source_span.dart';

import '../../models/source_region.dart';

/// Where a link's destination is written in the source.
///
/// For an inline link, `[text](destination)`, this is the text between the
/// parentheses, without a title. For a reference link, `[text][label]`, it is
/// the destination of the `[label]: destination` definition, so every link
/// that uses one definition shares one [LinkDestination] object.
@immutable
final class LinkDestination {
  const LinkDestination(this.span, {required this.isAngleBracketed});

  /// The destination as written, without enclosing `<` and `>`.
  final FileSpan span;

  /// Whether the destination is enclosed in `<` and `>`, which lets it hold
  /// spaces and unbalanced parentheses.
  final bool isAngleBracketed;

  /// The destination as written, without enclosing `<` and `>`.
  String get text => span.text;
}

/// A Markdown link or image found in a document.
@immutable
final class MarkdownLink {
  const MarkdownLink({required this.span, required this.destination});

  /// The whole link, from its `[` or `![` to its last character.
  final FileSpan span;

  /// Where the link's destination is written.
  final LinkDestination destination;

  /// The destination as written, without enclosing `<` and `>` or a title.
  String get target => destination.text;

  /// The 1-based region of [span], for diagnostics.
  SourceRegion get region => SourceRegion(
    startLine: span.start.line + 1,
    startColumn: span.start.column + 1,
    endLine: span.end.line + 1,
    endColumn: span.end.column + 1,
  );
}

/// A link reference definition, `[label]: destination "title"`.
@immutable
final class LinkDefinition {
  const LinkDefinition({required this.label, required this.destination, required this.end});

  /// The label, normalized so that labels that differ only in case or in
  /// runs of whitespace are equal.
  final String label;

  /// Where the definition's destination is written.
  final LinkDestination destination;

  /// The offset after the definition's line ending.
  final int end;
}
