// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import '../models/skill_rule.dart';
import '../models/validation_result.dart';
import 'reporter.dart';

/// Machine-readable JSON array reporter.
class JsonReporter implements Reporter {
  JsonReporter({StringSink? out, StringSink? err, this.pretty = true})
    : _out = out ?? stdout,
      _err = err ?? stderr;

  final StringSink _out;
  final StringSink _err;
  final bool pretty;

  @override
  void onDirectoryEvaluating(String directoryPath) {}

  @override
  void onDirectoryError(String directoryPath, String message) {}

  @override
  void onSkillEvaluating(String skillName) {}

  @override
  void onSkillValidationComplete(ValidationResult result) {}

  @override
  void onFixApplied(String skillName) {}

  @override
  void onDryRunProposed({
    required String skillName,
    String? targetSkillName,
    required String originalContent,
    required String currentContent,
  }) {}

  @override
  void onSkillRenamed(String oldSkillName, String targetSkillName) {}

  @override
  void onStaleIgnoreFound({
    required String ruleId,
    required String skillName,
    required String fullPath,
  }) {}

  @override
  void onNoSkillsFound(String message) {}

  @override
  void onIndividualSkillHint(String message) {}

  @override
  void onFixFailed({required String ruleName, required Object error}) {
    _err.writeln(
      "${Reporter.toolErrorPrefix} could not apply the '$ruleName' fix.\n"
      '  This is a bug in skills_lint, not a problem with your skill.\n'
      '  Your skill was left unmodified. Cause: $error',
    );
  }

  @override
  void onRenameFailed({
    required String oldSkillName,
    required String targetSkillName,
    required Object error,
  }) {
    _err.writeln(
      "${Reporter.toolErrorPrefix} could not rename skill directory from '$oldSkillName' to '$targetSkillName'.\n"
      '  This is a bug in skills_lint, not a problem with your skill.\n'
      "  Your skill directory was left at '$oldSkillName'. Cause: $error",
    );
  }

  @override
  void onRenameTargetExists({
    required String oldSkillName,
    required String targetSkillName,
    required String destinationPath,
  }) {
    _err.writeln(
      "${Reporter.toolErrorPrefix} cannot rename skill directory from '$oldSkillName' to '$targetSkillName': destination directory '$destinationPath' already exists.\n"
      '  This is a bug in skills_lint, not a problem with your skill.\n'
      "  Your skill directory was left at '$oldSkillName'.",
    );
  }

  @override
  void onBaselineFailed(String ignorePath, Object error) {
    _err.writeln(
      "${Reporter.toolErrorPrefix} failed to generate baseline file at '$ignorePath'.\n"
      '  This is a bug in skills_lint, not a problem with your skill.\n'
      '  Your baseline file was left unmodified. Cause: $error',
    );
  }

  @override
  void onSessionComplete(List<ValidationResult> results, {List<SkillRule> customRules = const []}) {
    final List<Map<String, Object?>> jsonList = results.map((r) => r.toJson()).toList();
    final encoder = pretty ? const JsonEncoder.withIndent('  ') : const JsonEncoder();
    _out.writeln(encoder.convert(jsonList));
  }
}
