// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import '../models/skill_rule.dart';
import '../models/validation_result.dart';
import 'reporter.dart';

/// Human-readable streaming text reporter.
class TextReporter implements Reporter {
  TextReporter({StringSink? out, StringSink? err, this.quiet = false, this.printWarnings = true})
    : _out = out ?? stdout,
      _err = err ?? stderr;

  /// Default message emitted when a skill is valid.
  static const String skillIsValidMsg = '  Skill is valid.';

  /// Default message emitted when a skill is invalid.
  static const String skillIsInvalidMsg = '  Skill is invalid:';

  /// Heading message emitted before listing warnings.
  static const String warningsMsg = 'Warnings:';

  /// Prefix message emitted before evaluating a directory.
  static const String evaluatingDirMsg = 'Evaluating directory:';

  /// Heading message emitted on directory-level errors.
  static const String directoryErrorMsg = 'Directory error:';

  /// Shared notice clarifying that an operational fault is an internal tool bug.
  static const String toolBugMsg = '  This is a bug in skills_lint, not a problem with your skill.';

  final StringSink _out;
  final StringSink _err;
  final bool quiet;
  final bool printWarnings;

  @override
  void onDirectoryEvaluating(String directoryPath) {
    if (!quiet) {
      _out.writeln('$evaluatingDirMsg $directoryPath');
    }
  }

  @override
  void onDirectoryError(String directoryPath, String message) {
    _err.writeln('  $directoryErrorMsg');
    _err.writeln('    - $message');
  }

  @override
  void onSkillEvaluating(String skillName) {
    if (!quiet) {
      _out.writeln('--- Validating skill: $skillName ---');
    }
  }

  @override
  void onSkillValidationComplete(ValidationResult result) {
    if (result.isValid) {
      if (!quiet) {
        _out.writeln('  $skillIsValidMsg');
      }
    } else {
      _err.writeln('  $skillIsInvalidMsg');
      for (final String error in result.errors) {
        _err.writeln('    - $error');
      }
    }

    if (printWarnings && result.warnings.isNotEmpty) {
      _out.writeln('  $warningsMsg');
      for (final String warning in result.warnings) {
        _out.writeln('    - $warning');
      }
    }
  }

  @override
  void onFixApplied(String skillName) {
    if (!quiet) {
      _out.writeln('  Applied fixes for $skillName');
    }
  }

  @override
  void onDryRunProposed({
    required String skillName,
    String? targetSkillName,
    required String originalContent,
    required String currentContent,
  }) {
    if (!quiet) {
      _out.writeln('  [Dry Run] Proposed changes for $skillName (SKILL.md):');
      _printDiff(originalContent, currentContent);
      if (targetSkillName != null && targetSkillName.isNotEmpty && targetSkillName != skillName) {
        _out.writeln('  [Dry Run] Proposed directory rename: $skillName -> $targetSkillName');
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
          _out.writeln('- Line ${i + 1}: $orig');
        }
        if (mod.isNotEmpty) {
          _out.writeln('+ Line ${i + 1}: $mod');
        }
      }
    }
  }

  @override
  void onSkillRenamed(String oldSkillName, String targetSkillName) {
    if (!quiet) {
      _out.writeln('  Renamed skill directory: $oldSkillName -> $targetSkillName');
    }
  }

  @override
  void onStaleIgnoreFound({
    required String ruleId,
    required String skillName,
    required String fullPath,
  }) {
    _out.writeln(
      "Stale ignore entry found for rule '$ruleId' in skill "
      "'$skillName' at '$fullPath'. Consider removing it.",
    );
  }

  @override
  void onNoSkillsFound(String message) {
    _err.writeln(message);
  }

  @override
  void onIndividualSkillHint(String message) {
    _err.writeln(message);
  }

  @override
  void onFixFailed({required String ruleName, required Object error}) {
    _err.writeln(
      "${Reporter.toolErrorPrefix} could not apply the '$ruleName' fix.\n"
      '$toolBugMsg\n'
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
      '$toolBugMsg\n'
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
      '$toolBugMsg\n'
      "  Your skill directory was left at '$oldSkillName'.",
    );
  }

  @override
  void onBaselineFailed(String ignorePath, Object error) {
    _err.writeln(
      "${Reporter.toolErrorPrefix} failed to generate baseline file at '$ignorePath'.\n"
      '$toolBugMsg\n'
      '  Your baseline file was left unmodified. Cause: $error',
    );
  }

  @override
  void onSessionComplete(
    List<ValidationResult> results, {
    List<SkillRule> customRules = const [],
  }) {}
}
