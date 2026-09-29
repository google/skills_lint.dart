// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../models/output_format.dart';
import '../models/skill_rule.dart';
import '../models/validation_result.dart';
import 'json_reporter.dart';
import 'sarif_reporter.dart';
import 'text_reporter.dart';

/// Contract for reporting validation events and results across formats.
abstract class Reporter {
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

  /// Line shared by every internal-error message, telling the user that the
  /// fault is in the tool and not in their skill.
  static const String _toolBugNotice =
      '  This is a bug in skills_lint, not a problem with your skill.';

  /// The stderr message every format writes for [onFixFailed].
  static String fixFailedMessage({required String ruleName, required Object error}) =>
      "$toolErrorPrefix could not apply the '$ruleName' fix.\n"
      '$_toolBugNotice\n'
      '  Your skill was left unmodified. Cause: $error';

  /// The stderr message every format writes for [onRenameFailed].
  static String renameFailedMessage({
    required String oldSkillName,
    required String targetSkillName,
    required Object error,
  }) =>
      "$toolErrorPrefix could not rename skill directory from '$oldSkillName' to '$targetSkillName'.\n"
      '$_toolBugNotice\n'
      "  Your skill directory was left at '$oldSkillName'. Cause: $error";

  /// The stderr message every format writes for [onRenameTargetExists].
  static String renameTargetExistsMessage({
    required String oldSkillName,
    required String targetSkillName,
    required String destinationPath,
  }) =>
      "$toolErrorPrefix cannot rename skill directory from '$oldSkillName' to '$targetSkillName': destination directory '$destinationPath' already exists.\n"
      '$_toolBugNotice\n'
      "  Your skill directory was left at '$oldSkillName'.";

  /// The stderr message every format writes for [onBaselineFailed].
  static String baselineFailedMessage(String ignorePath, Object error) =>
      "$toolErrorPrefix failed to generate baseline file at '$ignorePath'.\n"
      '$_toolBugNotice\n'
      '  Your baseline file was left unmodified. Cause: $error';

  /// Called when evaluation of a container directory begins.
  void onDirectoryEvaluating(String directoryPath);

  /// Called when validation of an individual skill folder begins.
  void onSkillEvaluating(String skillName);

  /// Called when validation of a single skill completes.
  void onSkillValidationComplete(ValidationResult result);

  /// Called when dry-run fix proposals are emitted.
  void onDryRunProposed({
    required String skillName,
    String? targetSkillName,
    required String originalContent,
    required String currentContent,
  });

  /// Called when fixes are written to disk for [skillName].
  void onFixApplied(String skillName);

  /// Called when a rule fix fails due to an internal exception.
  void onFixFailed({required String ruleName, required Object error});

  /// Called when a skill directory is renamed on disk.
  void onSkillRenamed(String oldSkillName, String targetSkillName);

  /// Called when a skill directory rename is blocked because the destination exists.
  void onRenameTargetExists({
    required String oldSkillName,
    required String targetSkillName,
    required String destinationPath,
  });

  /// Called when a skill directory rename fails due to an internal exception.
  void onRenameFailed({
    required String oldSkillName,
    required String targetSkillName,
    required Object error,
  });

  /// Called when an ignore entry was not matched by any finding.
  void onStaleIgnoreFound({
    required String ruleId,
    required String skillName,
    required String fullPath,
  });

  /// Called when no skills were found across specified directories.
  void onNoSkillsFound(String message);

  /// Called when a single skill folder was passed to `-d`.
  void onIndividualSkillHint(String message);

  /// Called when a directory listing or structural failure occurs.
  void onDirectoryError(String directoryPath, String message);

  /// Called when saving a baseline ignore file fails.
  void onBaselineFailed(String ignorePath, Object error);

  /// Called at the end of the validation session with all accumulated results.
  void onSessionComplete(List<ValidationResult> results, {List<SkillRule> customRules = const []});
}
