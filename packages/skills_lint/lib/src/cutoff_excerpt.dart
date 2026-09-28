// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Shared helper for "field is N characters; max is M" diagnostics that
// also show a |HERE| cutoff excerpt so the author can see exactly
// where the value went over.
//
// Used by both DescriptionLengthRule and the compatibility-length
// check in ValidYamlMetadataRule. Keep the message shape consistent
// across rules so downstream tooling that parses lint output doesn't
// have to learn two formats.

import 'length_limit.dart';

/// Number of characters of context to show on either side of the cutoff.
const int _excerptContextChars = 40;

/// Builds a length-overflow diagnostic for a frontmatter field whose
/// value is longer than `limit.maxLength`.
///
/// Output shape (placeholders shown in backticks):
///
///     `fieldName` field is `N` characters; maximum is `maxLength`.
///     Cutoff: ...`context`|HERE|`context`... (see `docUrl`)
///
/// The `|HERE|` marker sits at character `maxLength`, so the message does not
/// repeat the position. When [LengthLimit.isConfigured] is true,
/// `maximum is` reads `configured maximum is`, and:
///
/// * a limit below the specification maximum omits the `(see ...)` clause,
///   because the limit is a repository policy rather than a specification
///   requirement;
/// * a limit above the specification maximum adds
///   `(specification maximum is specMaxLength)` after the configured maximum,
///   because the value also breaks the specification.
///
/// The `(see ...)` clause is also omitted when [docUrl] is null. Newlines in
/// the excerpt are escaped to `\n` so the message stays on one line.
String buildLengthDiagnostic({
  required String fieldName,
  required String value,
  required LengthLimit limit,
  String? docUrl,
}) {
  final String excerpt = _buildCutoffExcerpt(value, limit.maxLength);
  final docsClause = limit.isBelowSpec || docUrl == null ? '' : ' (see $docUrl)';
  final String maximumClause = switch (limit) {
    LengthLimit(isAboveSpec: true) =>
      'configured maximum is ${limit.maxLength} '
          '(specification maximum is ${limit.specMaxLength})',
    LengthLimit(isConfigured: true) => 'configured maximum is ${limit.maxLength}',
    _ => 'maximum is ${limit.maxLength}',
  };
  return '$fieldName field is ${value.length} characters; '
      '$maximumClause. '
      'Cutoff: $excerpt'
      '$docsClause';
}

/// Builds a rich Markdown length-overflow diagnostic for SARIF and PR review comments.
///
/// Unlike the one-line [buildLengthDiagnostic], the Markdown form also states
/// how many characters are over the limit. [limit] and [docUrl] otherwise
/// behave as in [buildLengthDiagnostic].
String buildLengthMarkdownDiagnostic({
  required String fieldName,
  required String value,
  required LengthLimit limit,
  String? docUrl,
}) {
  final int maxLength = limit.maxLength;
  final int overCount = value.length - maxLength;
  final String excerpt = _buildCutoffExcerpt(value, maxLength);
  final String boldExcerpt = excerpt.replaceAll('|HERE|', '**|HERE|**');
  final docsClause = limit.isBelowSpec || docUrl == null
      ? ''
      : '\n\n*(See [Agent Skills Specification]($docUrl))*';
  final heading = limit.isConfigured
      ? 'exceeds configured maximum length'
      : 'exceeds maximum allowed length';
  final String limitClause = switch (limit) {
    LengthLimit(isAboveSpec: true) =>
      'over the configured **$maxLength** limit; '
          'the specification maximum is **${limit.specMaxLength}**',
    LengthLimit(isConfigured: true) => 'over the configured **$maxLength** limit',
    _ => 'over the **$maxLength** limit',
  };
  return '**Frontmatter `$fieldName` $heading.**\n\n'
      '**${value.length}** characters (**$overCount** characters $limitClause).\n\n'
      '**Cutoff excerpt:**\n'
      '> $boldExcerpt'
      '$docsClause';
}

String _buildCutoffExcerpt(String value, int maxLength) {
  final int start = (maxLength - _excerptContextChars).clamp(0, value.length);
  final int end = (maxLength + _excerptContextChars).clamp(0, value.length);
  final String before = value.substring(start, maxLength);
  final String after = value.substring(maxLength, end);
  final leadingEllipsis = start > 0 ? '...' : '';
  final trailingEllipsis = end < value.length ? '...' : '';
  final String escapedBefore = _escapeForOneLine(before);
  final String escapedAfter = _escapeForOneLine(after);
  return '$leadingEllipsis$escapedBefore|HERE|$escapedAfter$trailingEllipsis';
}

String _escapeForOneLine(String s) {
  return s.replaceAll('\n', r'\n').replaceAll('\r', r'\r');
}
