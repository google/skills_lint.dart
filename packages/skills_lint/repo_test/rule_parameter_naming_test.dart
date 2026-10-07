// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Rule parameter names in [RuleRegistry.allChecks] are kebab-case, and none
/// starts with a word of its rule's name.
///
/// Why this matters:
/// - A parameter name is both a `skills_lint.yaml` key and part of a CLI
///   flag. Renaming it later breaks users, so it has to be right the first
///   time.
/// - Mixing `_` and `-` in one flag is hard to type and to remember.
/// - The flag already starts with the rule name. A parameter that starts with
///   a word of the rule name was namespaced again by an author who did not
///   know that, as in `--description-too-long-description-length-max`. A
///   rule-name word later in the parameter, as in
///   `--published-skill-name-package-name`, can name something else and is
///   allowed.
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

  test('rule parameters are kebab-case and do not start with a rule-name word', () {
    final List<String> found = [
      for (final MapEntry<String, String> e in problems.entries)
        if (!misnamedAllowlist.contains(e.key)) '${e.key}: ${e.value}',
    ]..sort();
    expect(
      found,
      isEmpty,
      reason:
          'Rename these rule parameters. Use lowercase words joined by "-". The CLI flag '
          'is --<rule>-<param>, so do not start the parameter with a word of the rule '
          'name:\n${found.join('\n')}',
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
  final String firstWord = _words(param).first;
  final problems = [
    if (!_kebabCase.hasMatch(param)) 'not kebab-case',
    if (_words(check.name).contains(firstWord))
      '--${check.parameterFlag(param)} restates "$firstWord" from the rule name',
  ];
  return problems.isEmpty ? null : problems.join('; ');
}

List<String> _words(String name) => name.split(RegExp('[-_]'));
