// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:meta/meta.dart';

import 'write_boundary.dart';

/// What `--fix` may change for one skill.
///
/// A fix is written only when both of these allow it, and a denial from
/// either one wins:
///
/// * [mayFix], the rule's `fix` setting, resolved like its severity: the
///   command line, then the target's rules, then the global rules.
/// * [boundary], the directories the write may land in, which `write_allow`
///   and `--allow-write` widen.
///
/// Widening the boundary never turns a fix on, and `fix` never depends on
/// paths.
@immutable
final class WritePolicy {
  const WritePolicy({required this.boundary, required this.mayFix});

  /// Where the skill's writes and renames may land.
  final WriteBoundary boundary;

  /// Whether the fix of the rule named `ruleName` may run.
  final bool Function(String ruleName) mayFix;
}
