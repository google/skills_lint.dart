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
  /// Creates a fixer for a single skill.
  ///
  /// * [validator] validates each candidate fix against the skill's rules.
  /// * [applyIgnores] marks the diagnostics that the skill's ignore entries
  ///   cover, so that ignored findings don't count when comparing candidates.
  /// * [onFixFailed] receives the rule name and error when a rule's fix throws.
  /// * [mayFix] decides whether the rule named `ruleName` may run its fix.
  ///   Defaults to allowing every rule.
  SkillFixer({
    required this.validator,
    required this.applyIgnores,
    required this.onFixFailed,
    this.mayFix = _fixEveryRule,
  });

  static bool _fixEveryRule(String ruleName) => true;

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

  /// Whether the fix of the rule named `ruleName` may run.
  final bool Function(String ruleName) mayFix;

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
    var passes = 0;
    // Each pass either keeps a fix and counts, or settles and ends the loop.
    while (!settled && passes < maxPasses) {
      settled = true;
      for (final FixableRule rule in validator.rules.whereType<FixableRule>()) {
        if (!mayFix(rule.name)) {
          continue;
        }
        final Set<String>? ignoredSubjects = _ignoredSubjects(current, rule.name);
        if (ignoredSubjects == null) {
          continue;
        }
        switch (await _tryFix(rule, current, ignoredSubjects, canRename: canRename)) {
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
      if (!settled) {
        passes++;
      }
    }
    return _outcome(current, appliedRuleNames, skippedFixes, settled: settled, passes: passes);
  }

  /// Runs [rule]'s fix on the content of [current], leaving the findings with
  /// [ignoredSubjects], and validates the result.
  ///
  /// Returns `null` when the fix throws or changes nothing, and
  /// [_NeedsRename] when [canRename] is false and the fix changes `name` to a
  /// valid name that differs from the directory's.
  Future<_Attempt?> _tryFix(
    FixableRule rule,
    ValidationResult current,
    Set<String> ignoredSubjects, {
    required bool canRename,
  }) async {
    final SkillContext context = current.context!;
    final String fixedContent;
    try {
      fixedContent = await rule.fix(context, ignoredSubjects: ignoredSubjects);
      // Only built-in rules implement FixableRule, so any throw from a fix,
      // Error included, is a skills_lint bug that onFixFailed reports.
      // Catching everything stops one broken fixer from aborting the other
      // rules and skills.
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
      activeDirectoryName: wantedName,
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

  /// The subjects of the ignored findings of the rule named [ruleName] in
  /// [result].
  ///
  /// Is `null` when that rule's fix must not run: the rule reports no
  /// un-ignored finding, or an ignored finding has no subject, because a
  /// fixer can only leave a finding alone by its subject.
  static Set<String>? _ignoredSubjects(ValidationResult result, String ruleName) {
    final ignoredSubjects = <String>{};
    var hasUnignored = false;
    for (final ValidationError error in result.validationErrors) {
      if (error.ruleId != ruleName) {
        continue;
      }
      if (!error.isIgnored) {
        hasUnignored = true;
      } else if (error.subject case final String subject) {
        ignoredSubjects.add(subject);
      } else {
        return null;
      }
    }
    return hasUnignored ? ignoredSubjects : null;
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
    required int passes,
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
    passesWithKeptFixes: passes,
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
// Compare only errors once the warning severity is removed.
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
