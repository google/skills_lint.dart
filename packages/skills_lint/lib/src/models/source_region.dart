// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:meta/meta.dart';

/// A 1-based span within a source file.
///
/// All coordinates are 1-based, matching the SARIF 2.1.0 `region` object
/// (§3.30) and the YAML/Markdown conventions used by the rules that produce
/// them. [startLine] is required because SARIF rejects `startLine: 0`.
@immutable
class SourceRegion {
  const SourceRegion({required this.startLine, this.startColumn, this.endLine, this.endColumn})
    : assert(startLine >= 1, 'SARIF 2.1.0 requires startLine >= 1');

  /// Constructs a [SourceRegion] from a JSON map.
  factory SourceRegion.fromJson(Map<String, Object?> json) => SourceRegion(
    startLine: json[keyStartLine]! as int,
    startColumn: json[keyStartColumn] as int?,
    endLine: json[keyEndLine] as int?,
    endColumn: json[keyEndColumn] as int?,
  );

  /// JSON key for [startLine].
  static const String keyStartLine = 'startLine';

  /// JSON key for [startColumn].
  static const String keyStartColumn = 'startColumn';

  /// JSON key for [endLine].
  static const String keyEndLine = 'endLine';

  /// JSON key for [endColumn].
  static const String keyEndColumn = 'endColumn';

  /// The whole-file region, used when a diagnostic has no finer location.
  static const SourceRegion wholeFile = SourceRegion(startLine: 1);

  /// 1-based line number where the region starts (required by SARIF §3.30.2).
  final int startLine;

  /// 1-based column number where the region starts.
  ///
  /// When `null`, the region encompasses the entire starting line from column 1.
  final int? startColumn;

  /// 1-based line number where the region ends.
  ///
  /// When `null`, the region does not extend past [startLine].
  final int? endLine;

  /// 1-based column number where the region ends.
  ///
  /// When `null`, the region extends to the end of [endLine] (or [startLine] if [endLine] is null).
  final int? endColumn;

  /// Converts this region to a JSON map.
  Map<String, Object?> toJson() => {
    keyStartLine: startLine,
    if (startColumn != null) keyStartColumn: startColumn,
    if (endLine != null) keyEndLine: endLine,
    if (endColumn != null) keyEndColumn: endColumn,
  };
}
