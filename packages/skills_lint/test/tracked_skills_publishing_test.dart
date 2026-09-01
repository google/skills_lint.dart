// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:skills_lint/src/config_parser.dart';
import 'package:skills_lint/src/models/analysis_severity.dart';
import 'package:skills_lint/src/models/rule_config.dart';
import 'package:skills_lint/src/validation_session.dart';
import 'package:test/test.dart';

void main() {
  test('all tracked skills have prevent-skills-sh-publishing rule explicitly configured', () async {
    // Explanation:
    // Any skill in .agents/skills/ that is checked into version control is considered an internal skill.
    // It must explicitly have the `prevent-skills-sh-publishing` rule configured in skills_lint.yaml
    // to prevent accidental publishing (or explicitly disabled). Un-tracked / local dev skills (which are git-ignored)
    // are exempt so they can be published without friction.

    // 1. Get tracked files using git ls-files
    final ProcessResult processResult = await Process.run('git', [
      'ls-files',
      '../../.agents/skills',
    ]);
    expect(processResult.exitCode, 0, reason: 'git ls-files should succeed');

    final output = processResult.stdout as String;
    final Iterable<String> lines = output.split('\n').where((line) => line.trim().isNotEmpty);

    final trackedSkillDirs = <String>{};
    for (final line in lines) {
      final List<String> parts = line.split('/');
      final int agentsIdx = parts.indexOf('.agents');
      if (agentsIdx != -1 && parts.length >= agentsIdx + 4 && parts[agentsIdx + 1] == 'skills') {
        trackedSkillDirs.add(parts[agentsIdx + 2]);
      }
    }

    expect(trackedSkillDirs, isNotEmpty, reason: 'Should find at least one tracked skill');

    // 2. Parse configuration
    final Configuration config = await ConfigParser.loadConfig();
    final session = ValidationSession(
      config: config,
      ignoreFileOverride: null,
      customRules: [],
      printWarnings: false,
      fastFail: false,
      quiet: true,
      generateBaseline: false,
      fix: false,
      fixApply: false,
    );

    for (final skillDir in trackedSkillDirs) {
      final expectedPath = '../../.agents/skills/$skillDir';
      final Map<String, RuleConfig> resolvedConfigs = session.resolveRuleConfigsForPath(
        expectedPath,
      );

      expect(
        resolvedConfigs['prevent-skills-sh-publishing']?.severity,
        AnalysisSeverity.error,
        reason:
            'The tracked skill "$skillDir" must have "prevent-skills-sh-publishing" explicitly configured in skills_lint.yaml.',
      );
    }
  });
}
