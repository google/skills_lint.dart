// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import '../models/output_format.dart';
import '../models/skill_rule.dart';
import '../models/skipped_fix.dart';
import '../models/validation_result.dart';
import 'json_reporter.dart';
import 'sarif_reporter.dart';
import 'text_reporter.dart';
import 'tool_error_messages.dart';

/// Contract for reporting validation events and results across formats.
abstract class Reporter {
  /// Creates a reporter writing normal output to [out] (defaulting to
  /// [stdout]) and operational failure messages to [err] (defaulting to
  /// [stderr]).
  Reporter({StringSink? out, StringSink? err}) : out = out ?? stdout, err = err ?? stderr;

  /// Creates a reporter instance corresponding to [format].
  factory Reporter.fromFormat(
    OutputFormat format, {
    StringSink? out,
    StringSink? err,
    bool quiet = false,
    bool printWarnings = true,
    bool pretty = true,
    String? toolVersion,
  }) {
    switch (format) {
      case OutputFormat.text:
        return TextReporter(out: out, err: err, quiet: quiet, printWarnings: printWarnings);
      case OutputFormat.json:
        return JsonReporter(out: out, err: err, pretty: pretty);
      case OutputFormat.sarif:
        return SarifReporter(out: out, err: err, pretty: pretty, toolVersion: toolVersion);
    }
  }

  /// Prefix used for internal tool failure messages routed to stderr.
  static const String toolErrorPrefix = 'skills_lint internal error:';

  /// Destination for normal report output.
  final StringSink out;

  /// Destination for operational failure messages.
  final StringSink err;

  /// Called when evaluation of a container directory begins.
  void onDirectoryEvaluating(String directoryPath) {}

  /// Called when validation of an individual skill folder begins.
  void onSkillEvaluating(String skillName) {}

  /// Called when validation of a single skill completes.
  void onSkillValidationComplete(ValidationResult result) {}

  /// Called when dry-run fix proposals are emitted.
  void onDryRunProposed({
    required String skillName,
    String? targetSkillName,
    required String originalContent,
    required String currentContent,
  }) {}

  /// Called when the fixes of the rules named [ruleNames] are written to
  /// disk for [skillName].
  void onFixesWritten(String skillName, {required List<String> ruleNames}) {}

  /// Called by the session once it has fixed a skill and validated it again,
  /// with the result of that validation.
  ///
  /// When fixes are written, this replaces [onSkillValidationComplete] for a
  /// skill whose fixes changed it, and [result] is the one that sets the exit
  /// code. With [dryRun], nothing was written, and [result] is the skill as
  /// the fixes would leave it.
  void onFixedSkillValidationComplete(ValidationResult result, {bool dryRun = false}) {}

  /// Called when the fixer drops a rule's fix for [skillName] because the fix
  /// would not lower the skill's errors, then warnings.
  void onFixSkipped(String skillName, SkippedFix skipped) {}

  /// Called when the fixes for [skillName] still change the skill after
  /// [passes] passes.
  void onFixesDidNotSettle({required String skillName, required int passes}) {}

  /// Called when a rule fix fails due to an internal exception.
  void onFixFailed({required String ruleName, required Object error}) {
    err.writeln(ToolErrorMessages.fixFailedMessage(ruleName: ruleName, error: error));
  }

  /// Called when a skill directory is renamed on disk.
  void onSkillRenamed(String oldSkillName, String targetSkillName) {}

  /// Called when a skill directory rename is blocked because the destination exists.
  void onRenameTargetExists({
    required String oldSkillName,
    required String targetSkillName,
    required String destinationPath,
  }) {
    err.writeln(
      ToolErrorMessages.renameTargetExistsMessage(
        oldSkillName: oldSkillName,
        targetSkillName: targetSkillName,
        destinationPath: destinationPath,
      ),
    );
  }

  /// Called when a skill directory rename fails due to an internal exception.
  void onRenameFailed({
    required String oldSkillName,
    required String targetSkillName,
    required Object error,
  }) {
    err.writeln(
      ToolErrorMessages.renameFailedMessage(
        oldSkillName: oldSkillName,
        targetSkillName: targetSkillName,
        error: error,
      ),
    );
  }

  /// Called when an ignore entry was not matched by any finding.
  void onStaleIgnoreFound({
    required String ruleId,
    required String skillName,
    required String fullPath,
  }) {}

  /// Called when no skills were found across specified directories.
  void onNoSkillsFound(String message) {}

  /// Called when a single skill folder was passed to `-d`.
  void onIndividualSkillHint(String message) {}

  /// Called when a directory listing or structural failure occurs.
  void onDirectoryError(String directoryPath, String message) {}

  /// Called when saving a baseline ignore file fails.
  void onBaselineFailed(String ignorePath, Object error) {
    err.writeln(ToolErrorMessages.baselineFailedMessage(ignorePath: ignorePath, error: error));
  }

  /// Called at the end of the validation session with all accumulated results.
  void onSessionComplete(List<ValidationResult> results, {List<SkillRule> customRules = const []});
}
