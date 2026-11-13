// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:path/path.dart' as p;

import '../models/sarif/models/models.dart';
import '../models/sarif/sarif_serializer.dart';
import '../models/skill_context.dart';
import '../models/skill_rule.dart';
import '../models/validation_error.dart';
import '../rule_registry.dart';
import '../validator.dart';
import 'reporter.dart';
import 'text_reporter.dart';

/// SARIF 2.1.0 document reporter for CI and GitHub Code Scanning.
///
/// Writes the SARIF JSON document to [out] and prints any errors or reported
/// warnings to [err], so a redirected run such as
/// `skills_lint --format=sarif > skills-lint.sarif` leaves a clean SARIF file
/// on standard output while showing violations in the terminal or CI log.
class SarifReporter extends Reporter {
  SarifReporter({
    super.out,
    super.err,
    this.pretty = true,
    this.quiet = false,
    this.printWarnings = true,
    this.toolVersion,
  });

  final bool pretty;
  final bool quiet;
  final bool printWarnings;
  final String? toolVersion;

  /// Formats human-readable messages for [err] the way `--format=text` does.
  late final TextReporter _errReporter = TextReporter(
    out: err,
    err: err,
    quiet: quiet,
    printWarnings: printWarnings,
  );

  @override
  void onNoSkillsFound(String message) => _errReporter.onNoSkillsFound(message);

  @override
  void onIndividualSkillHint(String message) => _errReporter.onIndividualSkillHint(message);

  @override
  void onDirectoryError(String directoryPath, String message) =>
      _errReporter.onDirectoryError(directoryPath, message);

  @override
  void onSessionComplete(List<ValidationResult> results, {List<SkillRule> customRules = const []}) {
    final SarifLog sarif = SarifSerializer.toSarifLog(
      results,
      toolVersion: toolVersion,
      checkTypes: RuleRegistry.allChecks,
      customRules: customRules,
    );
    final encoder = pretty ? const JsonEncoder.withIndent('  ') : const JsonEncoder();
    out.writeln(encoder.convert(sarif.toJson()));
    _writeFindingsSummary(results);
  }

  /// Writes skills with errors or reported warnings to [err].
  ///
  /// Missing-target and directory-listing results have a `null`
  /// [ValidationResult.context] and are already reported as they happen via
  /// [onNoSkillsFound], [onIndividualSkillHint], or [onDirectoryError] under
  /// [Validator.pathDoesNotExist]. Unreadable skill files
  /// ([Validator.skillFileInaccessible]) also have a `null` context, so their
  /// skill name is derived from the parent directory of the `SKILL.md` path.
  void _writeFindingsSummary(List<ValidationResult> results) {
    for (final result in results) {
      final String? skillName = _skillNameForSummary(result);
      if (skillName == null) {
        continue;
      }
      final bool hasReportedWarnings = printWarnings && result.warnings.isNotEmpty;
      if (result.isValid && !hasReportedWarnings) {
        continue;
      }
      _errReporter
        ..onSkillEvaluating(skillName)
        ..onSkillValidationComplete(result);
    }
  }

  static String? _skillNameForSummary(ValidationResult result) {
    if (result.context case final SkillContext context) {
      return p.basename(context.directory.path);
    }
    for (final ValidationError error in result.validationErrors) {
      if (error.ruleId != Validator.pathDoesNotExist) {
        return p.basename(p.dirname(error.file));
      }
    }
    return null;
  }
}
