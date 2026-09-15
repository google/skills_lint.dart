// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// A region within an artifact, specified by line and column numbers.
class SarifRegion {
  SarifRegion({required this.startLine, this.startColumn, this.endLine, this.endColumn});

  /// Constructs a [SarifRegion] from a JSON map.
  factory SarifRegion.fromJson(Map<String, Object?> json) {
    return SarifRegion(
      startLine: json[keyStartLine]! as int,
      startColumn: json[keyStartColumn] as int?,
      endLine: json[keyEndLine] as int?,
      endColumn: json[keyEndColumn] as int?,
    );
  }

  /// JSON key for [startLine].
  static const String keyStartLine = 'startLine';

  /// JSON key for [startColumn].
  static const String keyStartColumn = 'startColumn';

  /// JSON key for [endLine].
  static const String keyEndLine = 'endLine';

  /// JSON key for [endColumn].
  static const String keyEndColumn = 'endColumn';

  /// 1-based start line number.
  final int startLine;

  /// 1-based start column number.
  final int? startColumn;

  /// 1-based end line number.
  final int? endLine;

  /// 1-based end column number.
  final int? endColumn;

  /// Converts this region to a JSON map.
  Map<String, Object?> toJson() => {
    keyStartLine: startLine,
    if (startColumn != null) keyStartColumn: startColumn,
    if (endLine != null) keyEndLine: endLine,
    if (endColumn != null) keyEndColumn: endColumn,
  };
}
