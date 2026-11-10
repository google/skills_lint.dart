// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:path/path.dart' as p;

import '../models/sarif/models/models.dart';
import '../models/sarif/sarif_serializer.dart';
import '../models/skill_context.dart';
import '../models/skill_rule.dart';
import '../models/validation_result.dart';
import '../rule_registry.dart';
import 'reporter.dart';
import 'text_reporter.dart';

/// SARIF 2.1.0 document reporter for CI and GitHub Code Scanning.
///
/// Writes the SARIF JSON document to [out] and prints any errors or enabled
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

  @override
  void onNoSkillsFound(String message) {
    err.writeln(message);
  }

  @override
  void onIndividualSkillHint(String message) {
    err.writeln(message);
  }

  @override
  void onDirectoryError(String directoryPath, String message) {
    err.writeln('  ${TextReporter.directoryErrorMsg}');
    err.writeln('    - $message');
  }

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

  /// Writes skills with errors or enabled warnings to [err].
  ///
  /// Results without a [ValidationResult.context], such as missing targets, are
  /// already reported as they happen via [onNoSkillsFound] or
  /// [onDirectoryError].
  void _writeFindingsSummary(List<ValidationResult> results) {
    final textReporter = TextReporter(
      out: err,
      err: err,
      quiet: quiet,
      printWarnings: printWarnings,
    );
    for (final result in results) {
      final SkillContext? context = result.context;
      if (context == null) {
        continue;
      }
      final bool hasReportedWarnings = printWarnings && result.warnings.isNotEmpty;
      if (result.isValid && !hasReportedWarnings) {
        continue;
      }
      textReporter
        ..onSkillEvaluating(p.basename(context.directory.path))
        ..onSkillValidationComplete(result);
    }
  }
}
