// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import '../models/output_format.dart';
import '../models/skill_rule.dart';
import '../models/skipped_fix.dart';
import '../models/validation_result.dart';
import 'fix_io_messages.dart';
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

  /// Called for each problem found in the configuration file.
  void onConfigurationWarning(String error) {
    err.writeln('Configuration warning: $error');
  }

  /// Called when a rule fix fails due to an internal exception.
  void onFixFailed({required String ruleName, required Object error}) {
    err.writeln(ToolErrorMessages.fixFailedMessage(ruleName: ruleName, error: error));
  }

  /// Called when a skill directory is renamed on disk.
  void onSkillRenamed(String oldSkillName, String targetSkillName) {}

  /// Called when `--fix` can't rename the skill directory [oldSkillName] to
  /// [targetSkillName], for example because the target exists or the
  /// parent directory is read-only.
  ///
  /// The fixes that need the new name are skipped, and the others still land.
  void onRenameBlocked({
    required String oldSkillName,
    required String targetSkillName,
    required String reason,
  }) {
    err.writeln(
      FixIoMessages.renameBlocked(
        oldSkillName: oldSkillName,
        targetSkillName: targetSkillName,
        reason: reason,
      ),
    );
  }

  /// Called when `--fix` can't write [skillMdPath], which leaves the skill
  /// unchanged.
  void onWriteFailed({required String skillMdPath, required Object error}) {
    err.writeln(FixIoMessages.writeFailed(skillMdPath: skillMdPath, error: error));
  }

  /// Called when `--fix` renamed the skill directory [fromPath] to [toPath],
  /// then couldn't write `SKILL.md`, and couldn't rename the directory back.
  void onRenamedButNotWritten({
    required String fromPath,
    required String toPath,
    required Object writeError,
    required Object undoError,
  }) {
    err.writeln(
      FixIoMessages.renamedButNotWritten(
        fromPath: fromPath,
        toPath: toPath,
        writeError: writeError,
        undoError: undoError,
      ),
    );
  }

  /// Called when an ignore entry was not matched by any finding.
  void onStaleIgnoreFound({
    required String ruleId,
    required String skillName,
    required String fullPath,
    String? subject,
  }) {}

  /// Called when no skills were found across specified directories.
  void onNoSkillsFound(String message) {}

  /// Called when a single skill folder was passed to `-d`.
  void onIndividualSkillHint(String message) {}

  /// Called when a directory listing or structural failure occurs.
  void onDirectoryError(String directoryPath, String message) {}

  /// Called for each part of an ignore file that could not be read, such as an
  /// entry with no `file_name`. [problem] names the file and, when
  /// there is one, the entry.
  void onIgnoreFileError(String problem) {
    err.writeln('Ignore file error: $problem');
  }

  /// Called before a baseline replaces [ignorePath], which had parts that
  /// could not be read and are not carried over.
  ///
  /// [entryCount] is the number of malformed entries, and [skills] names the
  /// skills they belong to. When [skills] is empty, the whole file could not
  /// be read.
  void onIgnoreEntriesDropped(
    String ignorePath, {
    required int entryCount,
    required List<String> skills,
  }) {
    if (skills.isEmpty) {
      err.writeln('Replacing $ignorePath without carrying over its unreadable contents.');
      return;
    }
    final entries = entryCount == 1 ? '1 malformed entry' : '$entryCount malformed entries';
    final String names = skills.map((skill) => '"$skill"').join(', ');
    err.writeln(
      'Replacing $ignorePath without carrying over $entries '
      '(${skills.length == 1 ? 'skill' : 'skills'} $names).',
    );
  }

  /// Called when saving a baseline ignore file fails.
  void onBaselineFailed(String ignorePath, Object error) {
    err.writeln(ToolErrorMessages.baselineFailedMessage(ignorePath: ignorePath, error: error));
  }

  /// Called at the end of the validation session with all accumulated results.
  void onSessionComplete(List<ValidationResult> results, {List<SkillRule> customRules = const []});
}
