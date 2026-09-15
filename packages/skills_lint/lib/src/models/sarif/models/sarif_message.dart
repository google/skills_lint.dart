// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// A human-readable message string.
class SarifMessage {
  SarifMessage({required this.text, this.markdown});

  /// Constructs a [SarifMessage] from a JSON map.
  factory SarifMessage.fromJson(Map<String, Object?> json) {
    return SarifMessage(
      text: (json[keyText] ?? '') as String,
      markdown: json[keyMarkdown] as String?,
    );
  }

  /// JSON key for [text].
  static const String keyText = 'text';

  /// JSON key for [markdown].
  static const String keyMarkdown = 'markdown';

  /// The text message content.
  final String text;

  /// Optional GitHub Flavored Markdown message content.
  final String? markdown;

  /// Converts this message to a JSON map.
  Map<String, Object?> toJson() => {keyText: text, if (markdown != null) keyMarkdown: markdown};
}
