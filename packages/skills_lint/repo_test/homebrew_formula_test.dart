// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'src/repo_paths.dart';

/// Checks `Formula/skills_lint.rb` against its template and the release, and
/// the package README's install commands against the tap and formula name.
void main() {
  test('matches its template, and its version follows the release rules', () async {
    // The release package generates the formula and is not a dependency of
    // skills_lint, so this runs its check.
    final ProcessResult result = await Process.run(Platform.resolvedExecutable, [
      'run',
      'bin/release.dart',
      'homebrew-formula',
      '--check',
    ], workingDirectory: p.join(repoRoot, 'release'));
    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
  });

  test('the package README installs the formula by its tap and name', () {
    // Published README pages never change, so the commands there must keep
    // working: renaming the tap or the formula breaks them.
    final workflow = loadYaml(_read('.github/workflows/homebrew.yaml')) as YamlMap;
    final tap = (workflow['env'] as YamlMap)['TAP'] as String;
    final String name = p.basenameWithoutExtension('Formula/skills_lint.rb');
    final List<String> readmeLines = [
      for (final String line in _read('packages/skills_lint/README.md').split('\n'))
        line.trimRight(),
    ];
    expect(readmeLines, contains('brew tap $tap https://github.com/google/skills_lint.dart'));
    expect(readmeLines, contains('brew install $tap/$name'));
  });
}

String _read(String path) => File(p.joinAll([repoRoot, ...p.posix.split(path)])).readAsStringSync();
