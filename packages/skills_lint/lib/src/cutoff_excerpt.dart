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

/// Number of characters of context to show on either side of the cutoff.
const int _excerptContextChars = 40;

/// Builds a length-overflow diagnostic for a frontmatter field whose
/// value is longer than [maxLength].
///
/// Output shape (placeholders shown in backticks):
///
///     `fieldName` field is `N` characters; maximum is `maxLength`.
///     Cutoff at character `maxLength`: ...`context`|HERE|`context`...
///     (see `docUrl`)
///
/// [specMaxLength] is the maximum set by the specification. Pass it when
/// [maxLength] comes from repository configuration. When the two differ,
/// `maximum is` reads `configured maximum is`, and:
///
/// * a [maxLength] below [specMaxLength] omits the `(see ...)` clause,
///   because the limit is a repository policy rather than a specification
///   requirement;
/// * a [maxLength] above [specMaxLength] adds
///   `(specification maximum is specMaxLength)` after the configured maximum,
///   because the value also breaks the specification.
///
/// The `(see ...)` clause is also omitted when [docUrl] is null. Newlines in
/// the excerpt are escaped to `\n` so the message stays on one line.
String buildLengthDiagnostic({
  required String fieldName,
  required String value,
  required int maxLength,
  int? specMaxLength,
  String? docUrl,
}) {
  final limit = _LengthLimit(maxLength, specMaxLength);
  final String excerpt = _buildCutoffExcerpt(value, maxLength);
  final String? url = limit.isBelowSpec ? null : docUrl;
  final docsClause = url != null ? ' (see $url)' : '';
  final String maximumClause = switch (limit) {
    _LengthLimit(isAboveSpec: true) =>
      'configured maximum is $maxLength (specification maximum is $specMaxLength)',
    _LengthLimit(isConfigured: true) => 'configured maximum is $maxLength',
    _ => 'maximum is $maxLength',
  };
  return '$fieldName field is ${value.length} characters; '
      '$maximumClause. '
      'Cutoff at character $maxLength: $excerpt'
      '$docsClause';
}

/// Builds a rich Markdown length-overflow diagnostic for SARIF and PR review comments.
///
/// [specMaxLength] and [docUrl] behave as in [buildLengthDiagnostic].
String buildLengthMarkdownDiagnostic({
  required String fieldName,
  required String value,
  required int maxLength,
  int? specMaxLength,
  String? docUrl,
}) {
  final limit = _LengthLimit(maxLength, specMaxLength);
  final int overCount = value.length - maxLength;
  final String excerpt = _buildCutoffExcerpt(value, maxLength);
  final String boldExcerpt = excerpt.replaceAll('|HERE|', '**|HERE|**');
  final String? url = limit.isBelowSpec ? null : docUrl;
  final docsClause = url != null ? '\n\n*(See [Agent Skills Specification]($url))*' : '';
  final heading = limit.isConfigured
      ? 'exceeds configured maximum length'
      : 'exceeds maximum allowed length';
  final String limitClause = switch (limit) {
    _LengthLimit(isAboveSpec: true) =>
      'over the configured **$maxLength** limit; '
          'the specification maximum is **$specMaxLength**',
    _LengthLimit(isConfigured: true) => 'over the configured **$maxLength** limit',
    _ => 'over the **$maxLength** limit',
  };
  return '**Frontmatter `$fieldName` $heading.**\n\n'
      '**${value.length}** characters (**$overCount** characters $limitClause).\n\n'
      '**Cutoff excerpt (at character $maxLength):**\n'
      '> $boldExcerpt'
      '$docsClause';
}

/// How an enforced length limit relates to the specification maximum.
class _LengthLimit {
  _LengthLimit(this.maxLength, this.specMaxLength);

  final int maxLength;
  final int? specMaxLength;

  /// Whether the limit comes from repository configuration that differs from
  /// the specification maximum.
  bool get isConfigured => specMaxLength != null && maxLength != specMaxLength;

  bool get isBelowSpec => isConfigured && maxLength < specMaxLength!;

  bool get isAboveSpec => isConfigured && maxLength > specMaxLength!;
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
