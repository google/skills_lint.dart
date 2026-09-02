// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:skills_lint/skills_lint.dart';
import 'package:test/test.dart';

void main() {
  test('Run skills linter mirroring config', () async {
    final Level oldLevel = Logger.root.level;
    Logger.root.level = Level.ALL;
    final StreamSubscription<LogRecord> subscription = Logger.root.onRecord.listen(
      (record) => stdout.writeln(record.message),
    );

    try {
      // Load configuration from the repository root skills_lint.yaml
      // to mirror what is configured in the repository.
      final Configuration config = await ConfigParser.loadConfig(path: '../../skills_lint.yaml');
      expect(
        config.directoryConfigs,
        isNotEmpty,
        reason: 'Configuration directoryConfigs should not be empty.',
      );

      final bool isValid = await validateSkills(
        skillDirPaths: [
          '../../.agents/skills',
          'skills',
          'example/skills/invalid',
          'example/skills/valid',
        ],
        config: config,
      );
      expect(isValid, isTrue, reason: 'Skills validation failed. See above for details.');
    } finally {
      Logger.root.level = oldLevel;
      await subscription.cancel();
    }
  });
}
