// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// One `uses:` reference to an action, reusable workflow or Docker image
/// outside this repository.
final class ActionPin {
  ActionPin(this.path, this.line, this.name, this.ref, this.comment);

  /// Repository-relative path of the workflow or action file, with `/`
  /// separators.
  final String path;

  /// 1-based line of the `uses:` value.
  final int line;

  /// The `uses:` value up to its ref: `owner/repo` or `owner/repo/path` for
  /// actions and reusable workflows, `docker://image` for Docker images.
  final String name;

  /// The rest of the `uses:` value after [name], starting with `@` (or `:`
  /// for a Docker tag). Empty if the value has no ref.
  final String ref;

  /// The first word of the comment on the same line, such as `v7.0.1`, or
  /// null if the line has no comment.
  final String? comment;

  /// The ref and version comment, as written after [name].
  String get pin => comment == null ? ref : '$ref # $comment';
}
