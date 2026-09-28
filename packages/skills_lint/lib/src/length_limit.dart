// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:meta/meta.dart';

/// An enforced maximum length for a frontmatter field, and how it relates
/// to the maximum set by the specification.
@immutable
class LengthLimit {
  const LengthLimit({required this.maxLength, this.specMaxLength});

  /// The enforced maximum length in characters.
  final int maxLength;

  /// The maximum set by the specification.
  ///
  /// Set it when [maxLength] can come from repository configuration. Leave it
  /// null for limits that cannot be configured.
  final int? specMaxLength;

  /// Whether [maxLength] comes from repository configuration that differs
  /// from [specMaxLength].
  bool get isConfigured => specMaxLength != null && maxLength != specMaxLength;

  /// Whether [maxLength] is a configured limit below [specMaxLength].
  bool get isBelowSpec => isConfigured && maxLength < specMaxLength!;

  /// Whether [maxLength] is a configured limit above [specMaxLength].
  bool get isAboveSpec => isConfigured && maxLength > specMaxLength!;
}
