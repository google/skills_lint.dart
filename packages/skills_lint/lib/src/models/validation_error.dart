// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'analysis_severity.dart';
import 'ignore_entry.dart';
import 'source_region.dart';

/// Represents a single validation error found during analysis.
class ValidationError {
  ValidationError({
    required this.ruleId,
    required this.file,
    required this.message,
    required this.severity,
    this.target,
    this.isIgnored = false,
    this.region,
    this.markdownMessage,
  });

  /// Constructs a [ValidationError] from a JSON map.
  factory ValidationError.fromJson(Map<String, Object?> json) => ValidationError(
    ruleId: json[keyRuleId]! as String,
    file: json[keyFile]! as String,
    message: json[keyMessage]! as String,
    severity: AnalysisSeverity.values.byName(json[keySeverity]! as String),
    target: json[keyTarget] as String?,
    isIgnored: json[keyIsIgnored] as bool? ?? false,
    region: json[keyRegion] != null
        ? SourceRegion.fromJson(json[keyRegion]! as Map<String, Object?>)
        : null,
    markdownMessage: json[keyMarkdownMessage] as String?,
  );

  /// JSON key for [ruleId].
  static const String keyRuleId = 'ruleId';

  /// JSON key for [file].
  static const String keyFile = 'file';

  /// JSON key for [message].
  static const String keyMessage = 'message';

  /// JSON key for [severity].
  static const String keySeverity = 'severity';

  /// JSON key for [target].
  static const String keyTarget = 'target';

  /// JSON key for [isIgnored].
  static const String keyIsIgnored = 'isIgnored';

  /// JSON key for [region].
  static const String keyRegion = 'region';

  /// JSON key for [markdownMessage].
  static const String keyMarkdownMessage = 'markdownMessage';

  /// The unique rule ID (e.g., 'description_too_long').
  final String ruleId;

  /// The file name context (e.g., 'SKILL.md' or relative path).
  final String file;

  /// The human-readable error message.
  final String message;

  /// The severity of the error.
  final AnalysisSeverity severity;

  /// Specific target within [file] that triggered the error, such as the raw
  /// path of a broken link.
  ///
  /// For link rules, [target] is the raw link destination as written in
  /// `SKILL.md`, with any `#anchor` or `%`-escapes preserved and any link
  /// title stripped.
  ///
  /// When non-null, `--generate-baseline` writes this value to
  /// [IgnoreEntry.target] so the generated baseline entry suppresses only
  /// findings with the same [target] rather than every finding of [ruleId] in
  /// [file]. Rules that emit at most one finding per file, or whose findings
  /// have no location-independent identifier, leave [target] `null`.
  ///
  /// Do not use line numbers or other position-dependent text as [target]:
  /// inserting or deleting lines above the finding would cause the baseline
  /// entry to stop matching and be reported as stale.
  ///
  /// Any [String] value is valid—including spaces, colons, quotes, Unicode, or
  /// malformed paths—because [IgnoreEntry] serializes via `jsonEncode` /
  /// `jsonDecode` and baseline deduplication compares `(ruleId, fileName,
  /// target)` tuples directly without string splitting. The rule must produce
  /// the exact same [String] when generating the baseline and on subsequent
  /// validation runs.
  final String? target;

  /// Whether this error has been ignored via configuration.
  bool isIgnored;

  /// Precise 1-based source location coordinates, if available.
  ///
  /// When `null`, the error applies to the entire file or lacks finer coordinate
  /// information, and formatters fall back to [SourceRegion.wholeFile].
  final SourceRegion? region;

  /// Optional GitHub Flavored Markdown formatted explanation for SARIF and PR review comments.
  ///
  /// When `null`, SARIF serializers and markdown formatters fall back to [message].
  final String? markdownMessage;

  /// Converts this error to a JSON-compatible map.
  Map<String, Object?> toJson() => {
    keyRuleId: ruleId,
    keyFile: file,
    keyMessage: message,
    keySeverity: severity.name,
    if (target != null) keyTarget: target,
    keyIsIgnored: isIgnored,
    if (region != null) keyRegion: region!.toJson(),
    if (markdownMessage != null) keyMarkdownMessage: markdownMessage,
  };
}
