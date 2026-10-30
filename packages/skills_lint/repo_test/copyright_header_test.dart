// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'src/package_directories.dart';

/// Checks the copyright header policy for every Dart file under
/// [dartSourceDirectories].
///
/// - A file we maintain starts with [_copyrightHeader]. Any four-digit year
///   is accepted.
/// - A user template, a Dart file in a skill's `references/` directory, has
///   no header. Users copy templates into their own packages, where the Dart
///   authors' copyright doesn't apply.

/// The header a maintained file starts with.
const String _copyrightHeader =
    '// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file\n'
    '// for details. All rights reserved. Use of this source code is governed by a\n'
    '// BSD-style license that can be found in the LICENSE file.';

/// The directory, inside a skill, that holds files users copy.
const String _userTemplateDirectory = 'references';

void main() {
  final List<String> files = _dartFiles();
  final List<String> templates = files.where(_isUserTemplate).toList();
  final List<String> maintained = files.where((f) => !_isUserTemplate(f)).toList();

  test('every maintained Dart file has the copyright header', () {
    final List<String> missing = maintained.where((f) => !_hasCopyrightHeader(f)).toList();
    expect(
      missing,
      isEmpty,
      reason:
          'Add this block as the first three lines of each file:\n$_copyrightHeader\n\n'
          "If the file is a template that users copy, move it into a skill's "
          '$_userTemplateDirectory/ directory instead.',
    );
  });

  test('no user template has the copyright header', () {
    final List<String> withHeader = templates.where(_hasCopyrightHeader).toList();
    expect(
      withHeader,
      isEmpty,
      reason:
          'Users copy these files into their own packages. Remove the Dart '
          "authors' copyright header.",
    );
  });
}

/// Every `.dart` file under [dartSourceDirectories], relative to the package
/// root.
List<String> _dartFiles() => [
  for (final String dir in dartSourceDirectories)
    if (Directory(dir).existsSync())
      for (final FileSystemEntity entity in Directory(dir).listSync(recursive: true))
        if (entity is File && entity.path.endsWith('.dart')) p.normalize(entity.path),
];

/// Whether [path] is in a skill's `references/` directory, such as
/// `skills/<name>/references/example.dart`.
bool _isUserTemplate(String path) {
  final List<String> parts = p.split(path);
  return parts.length > 3 && parts.first == 'skills' && parts[2] == _userTemplateDirectory;
}

final RegExp _copyrightPattern = RegExp(
  r'^// Copyright \(c\) \d{4}, the Dart project authors\. {2}Please see the AUTHORS file\n'
  r'// for details\. All rights reserved\. Use of this source code is governed by a\n'
  r'// BSD-style license that can be found in the LICENSE file\.',
);

bool _hasCopyrightHeader(String path) {
  // Normalize Windows line endings so the regex works on files checked out
  // with core.autocrlf enabled.
  final String normalized = File(path).readAsStringSync().replaceAll('\r\n', '\n');
  // Allow an optional shebang line (and any following blank lines) before the
  // copyright header.
  final String checkContent = normalized.startsWith('#!')
      ? normalized.substring(normalized.indexOf('\n') + 1).replaceFirst(RegExp(r'^\n*'), '')
      : normalized;
  return _copyrightPattern.hasMatch(checkContent);
}
