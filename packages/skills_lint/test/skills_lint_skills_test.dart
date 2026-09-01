// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('Run skills linter mirroring config', () async {
    final File configFile = _getConfigFile();
    expect(configFile.existsSync(), isTrue, reason: 'skills_lint.yaml missing');

    final String cliPath = p.normalize(p.absolute('bin/skills_lint.dart'));
    final ProcessResult result = await Process.run('dart', [
      cliPath,
    ], workingDirectory: configFile.parent.path);

    if (result.exitCode != 0) {
      stdout.write(result.stdout);
      stderr.write(result.stderr);
    }
    expect(result.exitCode, 0, reason: 'Skills validation failed. See output above.');
  });
}

File _getConfigFile() {
  Directory dir = Directory.current;
  while (dir.path != '/' && dir.path.isNotEmpty) {
    final configFile = File(p.join(dir.path, 'skills_lint.yaml'));
    if (configFile.existsSync()) {
      return configFile;
    }
    dir = dir.parent;
  }
  return File(p.normalize(p.absolute('../../skills_lint.yaml')));
}
