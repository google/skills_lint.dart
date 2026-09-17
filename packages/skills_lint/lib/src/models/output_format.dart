// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Supported output formats for validation results.
enum OutputFormat {
  /// Standard human-readable terminal output.
  text,

  /// Machine-readable raw JSON array of validation results.
  json,

  /// Standard SARIF 2.1.0 JSON document for CI and GitHub Code Scanning.
  sarif;

  /// Whether this output format supports auto-fixing operations.
  ///
  /// Structured machine formats ([OutputFormat.sarif], [OutputFormat.json]) do
  /// not support auto-fixing because applying fixes modifies the files
  /// described by the report.
  bool get supportsFixing => this == OutputFormat.text;

  /// Parses an [OutputFormat] from a string [value].
  ///
  /// Throws an [ArgumentError] if [value] is not a valid format name.
  static OutputFormat fromString(String value) {
    switch (value.toLowerCase()) {
      case 'text':
        return OutputFormat.text;
      case 'json':
        return OutputFormat.json;
      case 'sarif':
        return OutputFormat.sarif;
      default:
        throw ArgumentError.value(
          value,
          'value',
          'Unsupported output format "$value". Expected one of: text, json, sarif.',
        );
    }
  }
}

/// Returns `true` if auto-fixing is incompatible with the requested [format].
///
/// Auto-fixing cannot be combined with structured machine formats
/// ([OutputFormat.sarif], [OutputFormat.json]) because applying fixes modifies
/// the files described by the report.
bool hasInvalidFixFormatCombination({required bool fix, required OutputFormat format}) {
  return fix && !format.supportsFixing;
}
