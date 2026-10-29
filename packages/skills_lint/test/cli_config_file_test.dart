// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_lint/src/cli_config_file.dart';
import 'package:test/test.dart';

void main() {
  group('cliConfigFile', () {
    late Directory tempDir;
    late String configFile;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('cli_config_file_test.');
      configFile = p.join(tempDir.path, 'skills_lint.yaml');
      File(configFile).writeAsStringSync('skills_lint:\n');
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('is configPath when that file exists', () {
      expect(cliConfigFile(ignoreConfig: false, configPath: configFile), configFile);
    });

    test('is null when ignoreConfig is set, even when the file exists', () {
      expect(cliConfigFile(ignoreConfig: true, configPath: configFile), isNull);
    });

    test('is null when the file does not exist', () {
      expect(
        cliConfigFile(ignoreConfig: false, configPath: p.join(tempDir.path, 'missing.yaml')),
        isNull,
      );
    });
  });
}
