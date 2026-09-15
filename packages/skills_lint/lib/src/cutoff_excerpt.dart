// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Shared helper for "field is N characters; max is M" diagnostics that
// also show a |HERE| cutoff excerpt so the author can see exactly
// where the value went over.

/// Number of characters of context to show on either side of the cutoff.
const int _excerptContextChars = 40;

/// Builds a length-overflow diagnostic for a frontmatter field whose
/// value is longer than [maxLength].
String buildLengthDiagnostic({
  required String fieldName,
  required String value,
  required int maxLength,
  String? docUrl,
}) {
  final String excerpt = _buildCutoffExcerpt(value, maxLength);
  final docsClause = docUrl != null ? ' (see $docUrl)' : '';
  return '$fieldName field is ${value.length} characters; '
      'maximum is $maxLength. '
      'Cutoff at character $maxLength: $excerpt'
      '$docsClause';
}

/// Builds a rich Markdown length-overflow diagnostic for SARIF and PR review comments.
String buildLengthMarkdownDiagnostic({
  required String fieldName,
  required String value,
  required int maxLength,
  String? docUrl,
}) {
  final int overCount = value.length - maxLength;
  final String excerpt = _buildCutoffExcerpt(value, maxLength);
  final String boldExcerpt = excerpt.replaceAll('|HERE|', '**|HERE|**');
  final docsClause = docUrl != null ? '\n\n*(See [Agent Skills Specification]($docUrl))*' : '';
  return '**Frontmatter `$fieldName` exceeds maximum allowed length.**\n\n'
      '**${value.length}** characters (**$overCount** characters over the **$maxLength** limit).\n\n'
      '**Cutoff excerpt (at character $maxLength):**\n'
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
