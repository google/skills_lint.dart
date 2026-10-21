// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:meta/meta.dart';

/// The files `dart pub publish` would upload for the package that holds a
/// skill.
///
/// A [PubArchiveFiles] lists them. A [PubArchiveUnavailable] says why they
/// could not be listed, such as no `pubspec.yaml` or no `dart` on `PATH`.
@immutable
sealed class PubArchive {
  const PubArchive();
}

/// The files in the package archive that pub builds for [packageRoot].
@immutable
final class PubArchiveFiles extends PubArchive {
  const PubArchiveFiles({required this.packageRoot, required this.files});

  /// The absolute path of the directory that holds the package's
  /// `pubspec.yaml`.
  final String packageRoot;

  /// Each file in the archive, relative to [packageRoot], with `/` separators
  /// on every platform, such as `skills/my-pkg-setup/SKILL.md`.
  final Set<String> files;
}

/// The archive could not be built, for the user-facing [reason].
@immutable
final class PubArchiveUnavailable extends PubArchive {
  const PubArchiveUnavailable(this.reason);

  /// What went wrong and how to fix it, written for the person who runs the
  /// linter.
  final String reason;
}
