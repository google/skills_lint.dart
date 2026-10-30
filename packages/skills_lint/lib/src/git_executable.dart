// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;

/// Returns the executable to start for `git`, or `null` if there is none.
///
/// On macOS and Linux this is the bare name `git`, which the system looks up
/// on `PATH`.
///
/// On Windows, `dart:io` hands a bare name to `CreateProcessW`, which looks in
/// the current directory before `PATH`. A `git.exe` committed at the root of a
/// scanned repository would then run. So on Windows this returns the absolute
/// path of the first `git.exe` in an absolute `PATH` directory other than
/// [currentDirectory], or `null` if no such file exists.
///
/// The parameters default to the host's values, and let tests describe
/// another platform.
String? resolveGitExecutable({
  bool? isWindows,
  Map<String, String>? environment,
  String? currentDirectory,
  bool Function(String path)? fileExists,
}) {
  if (!(isWindows ?? Platform.isWindows)) {
    return 'git';
  }
  final String? pathVariable = _windowsPath(environment ?? Platform.environment);
  if (pathVariable == null) {
    return null;
  }
  final String cwd = currentDirectory ?? Directory.current.path;
  final bool Function(String) exists = fileExists ?? (path) => File(path).existsSync();
  for (final String rawEntry in pathVariable.split(';')) {
    final String entry = rawEntry.trim().replaceAll('"', '');
    if (entry.isEmpty || !p.windows.isAbsolute(entry) || p.windows.equals(entry, cwd)) {
      continue;
    }
    final String candidate = p.windows.join(entry, 'git.exe');
    if (exists(candidate)) {
      return candidate;
    }
  }
  return null;
}

/// The value of `PATH` in [environment], whose keys are case-insensitive on
/// Windows.
String? _windowsPath(Map<String, String> environment) {
  for (final MapEntry<String, String> entry in environment.entries) {
    if (entry.key.toUpperCase() == 'PATH') {
      return entry.value;
    }
  }
  return null;
}
