// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'src/published_files.dart';

/// Checks that the published package ships every skill in `skills/`, so
/// `dart run skills@ get` installs them, and ships none of their evals.
///
/// `.pubignore` excluded all of `skills/` from 0.5.2, and path dependencies
/// ignore `.pubignore`, so testing against a local checkout hid it. Only the
/// file list from `dart pub publish --dry-run` shows what consumers of the
/// hosted package get. Change this check if `package:skills` stops reading
/// skills from `skills/<name>/SKILL.md` in the hosted package.
void main() {
  late Set<String> published;

  setUpAll(() async {
    final ProcessResult result = await Process.run(Platform.resolvedExecutable, [
      'pub',
      'publish',
      '--dry-run',
    ]);
    published = parsePublishedFiles(result.stdout as String);
    expect(
      published,
      contains('pubspec.yaml'),
      reason:
          'dart pub publish --dry-run printed no file list:\n${result.stdout}\n${result.stderr}',
    );
  });

  test('the published package includes every skill in skills/', () {
    final List<String> skillFiles = [
      for (final FileSystemEntity entity in Directory('skills').listSync())
        if (entity is Directory && File(p.join(entity.path, 'SKILL.md')).existsSync())
          p.posix.join('skills', p.basename(entity.path), 'SKILL.md'),
    ];
    expect(skillFiles, isNotEmpty, reason: 'skills/ should hold at least one skill');
    expect(
      published,
      containsAll(skillFiles),
      reason: 'Remove the .pubignore pattern that excludes these skills.',
    );
  });

  test('the published package includes no skill evals', () {
    expect(
      published.where((path) => RegExp(r'^skills/[^/]+/evals/').hasMatch(path)),
      isEmpty,
      reason:
          'Exclude skills/*/evals/ in .pubignore. `dart run skills@ get` copies '
          'the whole skill directory into the consumer project.',
    );
  });
}
