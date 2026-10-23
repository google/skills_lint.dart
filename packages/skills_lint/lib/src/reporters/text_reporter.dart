// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../models/skill_rule.dart';
import '../models/skipped_fix.dart';
import '../models/validation_result.dart';
import 'reporter.dart';
import 'tool_error_messages.dart';

/// Human-readable streaming text reporter.
class TextReporter extends Reporter {
  TextReporter({super.out, super.err, this.quiet = false, this.printWarnings = true});

  /// Default message emitted when a skill is valid.
  static const String skillIsValidMsg = '  Skill is valid.';

  /// Default message emitted when a skill is invalid.
  static const String skillIsInvalidMsg = '  Skill is invalid:';

  /// Heading message emitted before listing warnings.
  static const String warningsMsg = 'Warnings:';

  /// Heading message emitted before the result `--fix --dry-run` predicts.
  static const String afterDryRunFixesMsg = 'After fixes, the skill would be:';

  /// Prefix message emitted before evaluating a directory.
  static const String evaluatingDirMsg = 'Evaluating directory:';

  /// Heading message emitted on directory-level errors.
  static const String directoryErrorMsg = 'Directory error:';

  final bool quiet;
  final bool printWarnings;

  @override
  void onDirectoryEvaluating(String directoryPath) {
    if (!quiet) {
      out.writeln('$evaluatingDirMsg $directoryPath');
    }
  }

  @override
  void onDirectoryError(String directoryPath, String message) {
    err.writeln('  $directoryErrorMsg');
    err.writeln('    - $message');
  }

  @override
  void onSkillEvaluating(String skillName) {
    if (!quiet) {
      out.writeln('--- Validating skill: $skillName ---');
    }
  }

  @override
  void onSkillValidationComplete(ValidationResult result) {
    if (result.isValid) {
      if (!quiet) {
        out.writeln('  $skillIsValidMsg');
      }
    } else {
      err.writeln('  $skillIsInvalidMsg');
      for (final String error in result.errors) {
        err.writeln('    - $error');
      }
    }

    if (printWarnings && result.warnings.isNotEmpty) {
      out.writeln('  $warningsMsg');
      for (final String warning in result.warnings) {
        out.writeln('    - $warning');
      }
    }
  }

  @override
  void onFixesWritten(String skillName, {required List<String> ruleNames}) {
    if (!quiet) {
      out.writeln('  Applied fixes for $skillName: ${ruleNames.join(', ')}');
    }
  }

  @override
  void onFixedSkillValidationComplete(ValidationResult result, {bool dryRun = false}) {
    final bool printsWarnings = printWarnings && result.warnings.isNotEmpty;
    // With --quiet, a valid skill without warnings prints nothing, so the
    // heading would stand alone.
    if (dryRun && (!quiet || !result.isValid || printsWarnings)) {
      out.writeln('  $afterDryRunFixesMsg');
    }
    onSkillValidationComplete(result);
  }

  @override
  void onRecheckAfterRenames() {
    if (!quiet) {
      out.writeln('Re-checking skills after directory renames:');
    }
  }

  @override
  void onFixSkipped(String skillName, SkippedFix skipped) {
    if (quiet) {
      return;
    }
    final String reason = switch (skipped) {
      SkippedFix(blockedDirectoryName: final String name) => 'directory $name already exists',
      SkippedFix(grownRuleNames: []) => 'it would not lower the number of errors or warnings',
      SkippedFix(:final grownRuleNames) => 'it would add ${grownRuleNames.join(', ')} diagnostics',
    };
    out.writeln('  Skipped the ${skipped.ruleName} fix: $reason.');
  }

  @override
  void onFixesDidNotSettle({required String skillName, required int passes}) {
    err.writeln(ToolErrorMessages.fixesDidNotSettleMessage(skillName: skillName, passes: passes));
  }

  @override
  void onDryRunProposed({
    required String skillName,
    String? targetSkillName,
    required String originalContent,
    required String currentContent,
  }) {
    if (!quiet) {
      out.writeln('  [Dry Run] Proposed changes for $skillName (SKILL.md):');
      _printDiff(originalContent, currentContent);
      if (targetSkillName != null && targetSkillName.isNotEmpty && targetSkillName != skillName) {
        out.writeln('  [Dry Run] Proposed directory rename: $skillName -> $targetSkillName');
      }
    }
  }

  void _printDiff(String original, String modified) {
    final List<String> origLines = original.split('\n');
    final List<String> modLines = modified.split('\n');
    final int maxLines = origLines.length > modLines.length ? origLines.length : modLines.length;
    for (var i = 0; i < maxLines; i++) {
      final String orig = i < origLines.length ? origLines[i] : '';
      final String mod = i < modLines.length ? modLines[i] : '';
      if (orig != mod) {
        if (orig.isNotEmpty) {
          out.writeln('- Line ${i + 1}: $orig');
        }
        if (mod.isNotEmpty) {
          out.writeln('+ Line ${i + 1}: $mod');
        }
      }
    }
  }

  @override
  void onSkillRenamed(String oldSkillName, String targetSkillName) {
    if (!quiet) {
      out.writeln('  Renamed skill directory: $oldSkillName -> $targetSkillName');
    }
  }

  @override
  void onStaleIgnoreFound({
    required String ruleId,
    required String skillName,
    required String fullPath,
  }) {
    out.writeln(
      "Stale ignore entry found for rule '$ruleId' in skill "
      "'$skillName' at '$fullPath'. Consider removing it.",
    );
  }

  @override
  void onNoSkillsFound(String message) {
    err.writeln(message);
  }

  @override
  void onIndividualSkillHint(String message) {
    err.writeln(message);
  }

  @override
  void onSessionComplete(
    List<ValidationResult> results, {
    List<SkillRule> customRules = const [],
  }) {}
}
