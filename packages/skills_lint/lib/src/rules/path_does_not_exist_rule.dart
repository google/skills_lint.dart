// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/analysis_severity.dart';
import '../models/skill_context.dart';
import '../models/skill_rule.dart';
import '../models/validation_error.dart';

/// Checks that a skill directory exists and contains a SKILL.md file.
class PathDoesNotExistRule extends SkillRule {
  PathDoesNotExistRule({required this.severity, this.excludeRegExp});

  static const String ruleName = 'path-does-not-exist';
  static const String excludeParameter = 'exclude';
  static const String _skillFileName = SkillContext.skillFileName;
  static const String _dirStructureUrl = 'https://agentskills.io/specification#directory-structure';

  @override
  final AnalysisSeverity severity;

  final RegExp? excludeRegExp;

  @override
  String get name => ruleName;

  @override
  Future<List<ValidationError>> validate(SkillContext context) async {
    final List<ValidationError> errors = [];
    final Directory dir = context.directory;
    final String normalizedPath = dir.path.replaceAll(r'\', '/');

    if (excludeRegExp != null && excludeRegExp!.hasMatch(normalizedPath)) {
      return errors;
    }

    if (!dir.existsSync()) {
      if (File(dir.path).existsSync()) {
        errors.add(
          ValidationError(
            ruleId: ruleName,
            file: dir.path,
            message: 'Path is not a directory: ${dir.path} (see $_dirStructureUrl)',
            markdownMessage:
                '**Path is not a directory:** `${dir.path}`\n\n'
                'Expected a directory containing `SKILL.md`.\n\n'
                '*(See [Agent Skills Specification]($_dirStructureUrl))*',
            severity: severity,
          ),
        );
      } else {
        errors.add(
          ValidationError(
            ruleId: ruleName,
            file: dir.path,
            message: 'Directory does not exist: ${dir.path} (see $_dirStructureUrl)',
            markdownMessage:
                '**Directory does not exist:** `${dir.path}`\n\n'
                '*(See [Agent Skills Specification]($_dirStructureUrl))*',
            severity: severity,
          ),
        );
      }
      return errors;
    }

    final skillMdFile = File(p.join(dir.path, _skillFileName));
    if (!skillMdFile.existsSync()) {
      final String dirName = p.basename(dir.path);
      errors.add(
        ValidationError(
          ruleId: ruleName,
          file: dir.path,
          message: '$_skillFileName is missing in directory: ${dir.path} (see $_dirStructureUrl)',
          markdownMessage:
              '**`SKILL.md` is missing in directory.**\n\n'
              '**How to fix:**\n'
              'Create a `SKILL.md` file in `$dirName/` defining the skill metadata and instructions.\n\n'
              '*(See [Agent Skills Specification]($_dirStructureUrl))*',
          severity: severity,
        ),
      );
    }

    return errors;
  }
}
