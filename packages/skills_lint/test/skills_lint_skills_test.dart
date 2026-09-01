// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_lint/skills_lint.dart';
import 'package:skills_lint/src/path_utils.dart';
import 'package:test/test.dart';

void main() {
  test('Run skills linter mirroring config', () async {
    final File configFile = _getConfigFile();
    expect(configFile.existsSync(), isTrue, reason: 'skills_lint.yaml missing');

    final Configuration config = await ConfigParser.loadConfig(path: configFile.path);
    expect(
      config.directoryConfigs,
      isNotEmpty,
      reason: 'Configuration directoryConfigs should not be empty.',
    );

    final List<LintTargetConfig> resolvedDirConfigs = [
      for (final dc in config.directoryConfigs)
        LintTargetConfig(
          path: p.normalize(p.join(configFile.parent.path, expandPath(dc.path))),
          ruleConfigs: dc.ruleConfigs,
          ignoreFile: dc.ignoreFile != null
              ? p.normalize(p.join(configFile.parent.path, expandPath(dc.ignoreFile!)))
              : null,
        ),
    ];

    final List<LintTargetConfig> resolvedIndConfigs = [
      for (final ic in config.individualSkillConfigs)
        LintTargetConfig(
          path: p.normalize(p.join(configFile.parent.path, expandPath(ic.path))),
          ruleConfigs: ic.ruleConfigs,
          ignoreFile: ic.ignoreFile != null
              ? p.normalize(p.join(configFile.parent.path, expandPath(ic.ignoreFile!)))
              : null,
        ),
    ];

    final inProcessConfig = Configuration(
      ruleConfigs: config.ruleConfigs,
      directoryConfigs: resolvedDirConfigs,
      individualSkillConfigs: resolvedIndConfigs,
    );

    final bool isValid = await validateSkills(config: inProcessConfig);
    expect(isValid, isTrue, reason: 'Skills validation failed. See above for details.');
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
