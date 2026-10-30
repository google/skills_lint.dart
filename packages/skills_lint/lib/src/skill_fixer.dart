// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:yaml/yaml.dart';

import 'fixable_rule.dart';
import 'models/fix_outcome.dart';
import 'models/skill_context.dart';
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
  /// Every kept fix strictly lowers the count of errors, then warnings, so
  /// the loop ends on its own. The limit stops a skill whose fixes take many
  /// small steps, or a fix or rule whose result changes between identical
  /// calls.
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
  /// [initial] must have a context. The fixer reads and writes no files.
  ///
  /// A fix that changes the skill's `name` plans a directory rename, and is
  /// judged as if the rename happens. With [canRename] false, every fix is
  /// judged under the current directory name, so a fix that needs the rename
  /// is dropped.
  Future<FixOutcome> fix(ValidationResult initial, {bool canRename = true}) async {
    var current = initial;
    final appliedRuleNames = <String>[];
    final skippedFixes = <String, SkippedFix>{};

    // Settled means a whole pass over the rules kept no fix.
    var settled = false;
    for (var pass = 0; pass < maxPasses && !settled; pass++) {
      settled = true;
      for (final FixableRule rule in validator.rules.whereType<FixableRule>()) {
        if (!_canFix(current, rule.name)) {
          continue;
        }
        switch (await _tryFix(rule, current, canRename: canRename)) {
          case null:
            continue;
          case _NeedsRename():
            skippedFixes[rule.name] = SkippedFix(
              ruleName: rule.name,
              grownRuleNames: const [],
              needsRename: true,
            );
          case _Candidate(:final ValidationResult result)
              when _DiagnosticCount.of(result).isLowerThan(_DiagnosticCount.of(current)):
            current = result;
            settled = false;
            skippedFixes.remove(rule.name);
            if (!appliedRuleNames.contains(rule.name)) {
              appliedRuleNames.add(rule.name);
            }
          case _Candidate(:final ValidationResult result):
            skippedFixes[rule.name] = SkippedFix(
              ruleName: rule.name,
              grownRuleNames: _grownRuleNames(before: current, after: result),
            );
        }
      }
    }
    return _outcome(current, appliedRuleNames, skippedFixes, settled: settled);
  }

  /// Runs [rule]'s fix on the content of [current] and validates the result.
  ///
  /// Returns `null` when the fix throws or changes nothing, and
  /// [_NeedsRename] when [canRename] is false and the fix changes `name` to a
  /// valid name that differs from the directory's.
  Future<_Attempt?> _tryFix(
    FixableRule rule,
    ValidationResult current, {
    required bool canRename,
  }) async {
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

    final String? wantedName = newDirectoryName(
      originalContent: context.rawContent,
      fixedContent: fixedContent,
    );
    // Content whose `name` differs from the directory is never kept: it would
    // leave the skill worse than before the fix.
    if (!canRename && wantedName != null && wantedName != context.activeDirectoryName) {
      return _NeedsRename();
    }
    final ValidationResult result = await validator.validateProposedContent(
      context,
      fixedContent,
      activeDirectoryName: wantedName ?? context.activeDirectoryName,
    );
    applyIgnores(result);
    return _Candidate(result);
  }

  /// The name to rename the skill directory to after a fix, or `null` to
  /// leave the directory alone.
  ///
  /// The directory follows the frontmatter `name` only when the fix changed
  /// it to a valid skill name.
  static String? newDirectoryName({required String originalContent, required String fixedContent}) {
    final String? nameBefore = NameFormatRule.skillNameOf(
      NameFormatRule.nameNodeOf(originalContent),
    )?.trim();
    final YamlNode? nameNodeAfter = NameFormatRule.nameNodeOf(fixedContent);
    final String? nameAfter = NameFormatRule.skillNameOf(nameNodeAfter)?.trim();
    if (nameBefore == null || nameAfter == null) {
      return null;
    }
    // The name becomes a directory name, so it must be text, not a plain `false` or `0x1f`.
    if (nameNodeAfter?.value is! String) {
      return null;
    }
    if (nameAfter == nameBefore || !NameFormatRule.isValidSkillName(nameAfter)) {
      return null;
    }
    return nameAfter;
  }

  /// Whether the fix of the rule named [ruleName] may run on [result]: the
  /// rule reports a diagnostic, and an ignore entry covers none of them.
  ///
  /// A fixer rewrites every finding of its rule, so it must not run when an
  /// ignore entry covers some of them.
  static bool _canFix(ValidationResult result, String ruleName) {
    final Iterable<ValidationError> findings = result.validationErrors.where(
      (e) => e.ruleId == ruleName,
    );
    return findings.isNotEmpty && findings.every((e) => !e.isIgnored);
  }

  /// Whether [result] has an un-ignored diagnostic from the rule named
  /// [ruleName].
  static bool _reports(ValidationResult result, String ruleName) =>
      result.validationErrors.any((e) => e.ruleId == ruleName && !e.isIgnored);

  /// The rules that report more diagnostics in [after] than in [before].
  static List<String> _grownRuleNames({
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
  }) => FixOutcome(
    result: result,
    appliedRuleNames: appliedRuleNames,
    // Report a dropped fix only if its rule still has diagnostics at the end.
    // A fix dropped in an early pass may stop mattering when a later fix
    // clears that rule's diagnostics.
    skippedFixes: [
      for (final SkippedFix skipped in skippedFixes.values)
        if (_reports(result, skipped.ruleName)) skipped,
    ],
    settled: settled,
  );
}

/// What running one rule's fix produced, before the fixer decides to keep it.
sealed class _Attempt {}

/// A fix that needs a directory rename that can't happen.
final class _NeedsRename extends _Attempt {}

/// A fix and the validation result of its content.
final class _Candidate extends _Attempt {
  _Candidate(this.result);

  final ValidationResult result;
}

// TODO(reidbaker-agent): https://github.com/google/skills_lint.dart/issues/140
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
