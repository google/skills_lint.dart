// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'fixable_rule.dart';
import 'models/fix_outcome.dart';
import 'models/skill_context.dart';
import 'models/skill_rule.dart';
import 'models/skipped_fix.dart';
import 'models/validation_error.dart';
import 'rules/name_format_rule.dart';
import 'validator.dart';

/// Applies fixes to one skill in memory until no fix makes it better.
///
/// A fix is kept only if it lowers the skill's count of errors, then
/// warnings, across all enabled rules. Rules don't need to know about each
/// other: a fix that breaks another rule is dropped and reported.
class SkillFixer {
  SkillFixer({required this.validator, required this.applyIgnores, required this.onFixFailed});

  /// The most passes over the fixable rules for one skill.
  ///
  /// Every kept fix lowers the count, and every pass but the last keeps a
  /// fix, so the loop ends on its own. Only a fix whose result changes
  /// between identical calls can reach this limit.
  static const int maxPasses = 10;

  /// Validates each candidate, with the skill's rules.
  final Validator validator;

  /// Marks the diagnostics of a result that the skill's ignore entries cover,
  /// so that they don't count.
  final void Function(ValidationResult result) applyIgnores;

  /// Called when a rule's fix throws.
  final void Function(String ruleName, Object error) onFixFailed;

  /// Fixes the skill that [initial] describes, without writing to disk.
  ///
  /// [initial] must have a context.
  Future<FixOutcome> fix(ValidationResult initial) async {
    var current = initial;
    final appliedRuleNames = <String>[];
    final skippedFixes = <String, SkippedFix>{};

    for (var pass = 1; pass <= maxPasses; pass++) {
      var keptAFix = false;
      for (final SkillRule rule in validator.rules) {
        if (rule is! FixableRule || !_reports(current, rule.name)) {
          continue;
        }
        final _Attempt? attempt = await _tryFix(rule, current);
        if (attempt == null) {
          continue;
        }
        final ValidationResult candidate = attempt.result;
        if (_DiagnosticCount.of(candidate).isLowerThan(_DiagnosticCount.of(current))) {
          current = candidate;
          keptAFix = true;
          skippedFixes.remove(rule.name);
          if (!appliedRuleNames.contains(rule.name)) {
            appliedRuleNames.add(rule.name);
          }
        } else {
          skippedFixes[rule.name] = SkippedFix(
            ruleName: rule.name,
            grownRuleIds: _grownRuleIds(before: current, after: candidate),
            blockedDirectoryName: attempt.blockedDirectoryName,
          );
        }
      }
      if (!keptAFix) {
        return _outcome(current, appliedRuleNames, skippedFixes, settled: true, passes: pass - 1);
      }
    }
    return _outcome(current, appliedRuleNames, skippedFixes, settled: false, passes: maxPasses);
  }

  /// Runs [rule]'s fix on the content of [current] and validates the result,
  /// or returns `null` when the fix throws or changes nothing.
  Future<_Attempt?> _tryFix(FixableRule rule, ValidationResult current) async {
    final SkillContext context = current.context!;
    final String fixedContent;
    try {
      fixedContent = await rule.fix(context);
      // A fixer is rule code: built in, or a custom rule that implements
      // FixableRule. Any throw from it, Error included, is a bug in that
      // rule, and onFixFailed reports it as a tool bug. Catching everything
      // stops one broken fixer from aborting the remaining rules and skills.
      // ignore: avoid_catches_without_on_clauses
    } catch (e) {
      onFixFailed(rule.name, e);
      return null;
    }
    if (fixedContent == context.rawContent) {
      return null;
    }

    final String plannedName =
        newDirectoryName(originalContent: context.rawContent, fixedContent: fixedContent) ??
        context.directoryName;
    // The rename can't happen if another directory has the name already, so
    // the candidate keeps the current name and is judged that way.
    final bool renameBlocked =
        plannedName != p.basename(context.directory.path) &&
        Directory(p.join(p.dirname(context.directory.path), plannedName)).existsSync();
    final ValidationResult result = await validator.validateContent(
      context.directory,
      fixedContent,
      directoryName: renameBlocked ? context.directoryName : plannedName,
    );
    applyIgnores(result);
    return _Attempt(result, blockedDirectoryName: renameBlocked ? plannedName : null);
  }

  /// The name to rename the skill directory to after a fix, or `null` to
  /// leave the directory alone.
  ///
  /// The directory follows the frontmatter `name` only when the fix changed
  /// it to a valid skill name.
  static String? newDirectoryName({required String originalContent, required String fixedContent}) {
    final String? originalName = NameFormatRule.skillNameOf(
      NameFormatRule.nameNodeOf(originalContent),
    )?.trim();
    final YamlNode? fixedNode = NameFormatRule.nameNodeOf(fixedContent);
    final String? fixedName = NameFormatRule.skillNameOf(fixedNode)?.trim();
    if (originalName == null || fixedName == null) {
      return null;
    }
    // The name becomes a directory name, so it must be text, not a plain `false` or `0x1f`.
    if (fixedNode?.value is! String) {
      return null;
    }
    if (fixedName == originalName || !NameFormatRule.isValidSkillName(fixedName)) {
      return null;
    }
    return fixedName;
  }

  static bool _reports(ValidationResult result, String ruleName) =>
      result.validationErrors.any((e) => e.ruleId == ruleName && !e.isIgnored);

  /// The rules that report more diagnostics in [after] than in [before].
  static List<String> _grownRuleIds({
    required ValidationResult before,
    required ValidationResult after,
  }) {
    final Map<String, int> countsBefore = _countsByRule(before);
    final Map<String, int> countsAfter = _countsByRule(after);
    return [
      for (final MapEntry(key: ruleId, value: count) in countsAfter.entries)
        if (count > (countsBefore[ruleId] ?? 0)) ruleId,
    ];
  }

  static Map<String, int> _countsByRule(ValidationResult result) {
    final counts = <String, int>{};
    for (final ValidationError error in result.validationErrors) {
      if (!error.isIgnored) {
        counts.update(error.ruleId, (count) => count + 1, ifAbsent: () => 1);
      }
    }
    return counts;
  }

  static FixOutcome _outcome(
    ValidationResult result,
    List<String> appliedRuleNames,
    Map<String, SkippedFix> skippedFixes, {
    required bool settled,
    required int passes,
  }) => FixOutcome(
    result: result,
    appliedRuleNames: appliedRuleNames,
    // A fix dropped in an early pass may no longer matter: a later fix can
    // clear that rule's diagnostics.
    skippedFixes: [
      for (final SkippedFix skipped in skippedFixes.values)
        if (_reports(result, skipped.ruleName)) skipped,
    ],
    settled: settled,
    passes: passes,
  );
}

/// The validation result of one fix, before the fixer decides to keep it.
class _Attempt {
  _Attempt(this.result, {required this.blockedDirectoryName});

  final ValidationResult result;

  /// See [SkippedFix.blockedDirectoryName].
  final String? blockedDirectoryName;
}

/// The un-ignored errors and warnings of a result, compared errors first.
class _DiagnosticCount {
  _DiagnosticCount.of(ValidationResult result)
    : errors = result.errors.length,
      warnings = result.warnings.length;

  final int errors;
  final int warnings;

  // Comparing errors first means a fix may add a warning while it clears an
  // error. A skill that has no errors after the fix then passes, as it would
  // have with the fix written unguarded.
  bool isLowerThan(_DiagnosticCount other) =>
      errors < other.errors || (errors == other.errors && warnings < other.warnings);
}
