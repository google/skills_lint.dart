// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Rule parameter names in [RuleRegistry.allChecks] are kebab-case, and the
/// generated `--<rule>-<param>` CLI flag repeats no word of the rule name.
///
/// Why this matters:
/// - A parameter name is both a `skills_lint.yaml` key and part of a CLI
///   flag. Renaming it later breaks users, so it has to be right the first
///   time.
/// - Mixing `_` and `-` in one flag is hard to type and to remember.
/// - The flag already starts with the rule name. Repeating a word from it
///   makes the flag long and says nothing new.
///
/// Revisit this if CLI flags stop being generated from the rule name and the
/// parameter name.
library;

import 'package:skills_lint/src/models/check_type.dart';
import 'package:skills_lint/src/rule_registry.dart';
import 'package:test/test.dart';

/// Parameters that break the convention and should be renamed.
///
/// Do not add entries; name the new parameter correctly instead. When a
/// parameter is renamed, remove it from this list. The test fails until you
/// do. Keys are `<rule>/<param>`.
const Set<String> misnamedAllowlist = {
  // TODO(reidbaker): https://github.com/google/skills_lint.dart/issues/102
  'published-skill-name/package_name',
  // TODO(reidbaker): https://github.com/google/skills_lint.dart/issues/102
  'published-skill-name/pubspec_path',
};

const String _self = 'repo_test/rule_parameter_naming_test.dart';

final RegExp _kebabCase = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');

void main() {
  final Map<String, String> problems = {};
  for (final CheckType check in RuleRegistry.allChecks) {
    for (final String param in check.parameterSchema.keys) {
      final String? problem = _problem(check, param);
      if (problem != null) {
        problems['${check.name}/$param'] = problem;
      }
    }
  }

  test('rule parameters are kebab-case and their flags repeat no rule-name word', () {
    final List<String> found = [
      for (final MapEntry<String, String> e in problems.entries)
        if (!misnamedAllowlist.contains(e.key)) '${e.key}: ${e.value}',
    ]..sort();
    expect(
      found,
      isEmpty,
      reason:
          'Rename these rule parameters. Use lowercase words joined by "-", and leave out '
          'words that the rule name already has:\n${found.join('\n')}',
    );
  });

  test('misnamedAllowlist only lists parameters that still break the convention', () {
    final List<String> stale = misnamedAllowlist.difference(problems.keys.toSet()).toList()..sort();
    expect(
      stale,
      isEmpty,
      reason:
          'Remove these entries from misnamedAllowlist in $_self. They were renamed, '
          'fixed, or no longer exist:\n${stale.join('\n')}',
    );
  });
}

/// Returns what is wrong with [param] of [check], or null if nothing is.
String? _problem(CheckType check, String param) {
  final Set<String> ruleWords = _words(check.name);
  final List<String> repeated = [
    for (final String word in _words(param))
      if (ruleWords.contains(word)) word,
  ];
  final problems = [
    if (!_kebabCase.hasMatch(param)) 'not kebab-case',
    if (repeated.isNotEmpty)
      '--${check.parameterFlag(param)} repeats "${repeated.join('", "')}" from the rule name',
  ];
  return problems.isEmpty ? null : problems.join('; ');
}

Set<String> _words(String name) => name.split(RegExp('[-_]')).toSet();
