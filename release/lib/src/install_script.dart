// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Writes the `install.sh` that a GitHub release ships.
library;

import 'release_exception.dart';

/// The line of `scripts/install.sh` that sets the default version.
const String _defaultVersionLine = r'VERSION="${VERSION:-latest}"';

/// Returns the install [script] with [version] as the version it installs
/// when `VERSION` is unset, so the copy attached to a release installs that
/// release.
///
/// Throws a [ReleaseException] unless [script] sets the default version to
/// `latest` on exactly one line.
String installScriptForVersion(String script, String version) {
  final List<String> lines = script.split('\n');
  final int count = lines.where((line) => line == _defaultVersionLine).length;
  if (count != 1) {
    throw ReleaseException(
      'install.sh has $count lines that read `$_defaultVersionLine`; expected 1.',
    );
  }
  return [
    for (final line in lines)
      if (line == _defaultVersionLine) 'VERSION="\${VERSION:-$version}"' else line,
  ].join('\n');
}
