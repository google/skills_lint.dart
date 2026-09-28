// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:meta/meta.dart';

import '../config_parser.dart';

/// A path to validate, together with where it came from.
///
/// A missing target is explained in terms of its origin: the declaration in a
/// configuration file, or the text typed on the command line. Internal to
/// skills_lint: it is not exported from the public library.
@immutable
class ValidationTarget {
  /// A target declared in a configuration, validated at its resolved path.
  ValidationTarget.fromConfiguration(LintTargetConfig target)
    : path = target.path,
      declaredBy = target,
      cliText = null;

  /// A target passed on the command line or through the API, where [typed] is
  /// the text before it was resolved to [path].
  const ValidationTarget.fromCommandLine(this.path, {required String typed})
    : cliText = typed,
      declaredBy = null;

  /// A default location the tool looked in without being asked.
  const ValidationTarget.byDefault(this.path) : declaredBy = null, cliText = null;

  /// The absolute path to validate.
  final String path;

  /// The configuration target that declared [path], if any.
  final LintTargetConfig? declaredBy;

  /// [path] as the caller typed it, for a command-line or API target.
  final String? cliText;
}
