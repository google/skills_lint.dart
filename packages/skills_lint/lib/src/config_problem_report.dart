// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'models/config_location.dart';
import 'models/config_problem.dart';

/// The text that the CLI prints for [problems].
///
/// Problems are grouped by configuration file. Each group starts with a header
/// that counts its problems, followed by one indented line per problem. A
/// footer says what happened and what to do next.
///
/// [ignored] is `true` when `--allow-misconfigured-keys` lets skills_lint run
/// without the problem entries, which makes the problems warnings.
String configProblemReport(List<ConfigProblem> problems, {required bool ignored}) {
  final kind = ignored ? 'warning' : 'error';
  final groups = <String?, List<ConfigProblem>>{};
  for (final problem in problems) {
    (groups[problem.location?.file] ??= []).add(problem);
  }
  final lines = <String>[];
  for (final MapEntry<String?, List<ConfigProblem>> group in groups.entries) {
    final String count = _count(group.value.length, 'configuration $kind');
    final String? file = group.key;
    lines
      ..add(file == null ? '$count:' : '${displayConfigPath(file)} has $count:')
      ..add('')
      ..addAll(_problemLines(group.value))
      ..add('');
  }
  final String? onlyFile = groups.length == 1 ? groups.keys.single : null;
  final inFile = onlyFile == null ? '' : ' in ${displayConfigPath(onlyFile)}';
  final int total = problems.length;
  lines.add(
    ignored
        ? 'skills_lint ran without ${total == 1 ? 'this entry' : 'these $total entries'}$inFile '
              'because of --allow-misconfigured-keys.'
        : 'skills_lint did not run. Fix ${total == 1 ? 'this error' : 'these $total errors'}$inFile '
              'and run again.',
  );
  return lines.join('\n');
}

/// One indented line per problem in [problems], with the messages aligned
/// after the locations.
Iterable<String> _problemLines(List<ConfigProblem> problems) {
  final List<String> locations = [
    for (final problem in problems)
      if (problem.location case final ConfigLocation location)
        formatConfigLocation(location)
      else
        '',
  ];
  final int width = locations.fold(
    0,
    (int widest, String l) => l.length > widest ? l.length : widest,
  );
  return [
    for (var i = 0; i < problems.length; i++)
      if (locations[i].isEmpty)
        '  ${problems[i].message}'
      else
        '  ${locations[i].padRight(width)}  ${problems[i].message}',
  ];
}

String _count(int n, String noun) => '$n $noun${n == 1 ? '' : 's'}';
