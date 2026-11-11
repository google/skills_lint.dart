import 'dart:io';
import 'dart:math';

import 'package:skills_lint/src/yaml_anchor_scanner.dart';
import 'package:skills_lint/src/yaml_limits.dart';
import 'package:yaml/yaml.dart';

double median(List<double> values) {
  final sorted = [...values]..sort();
  final mid = sorted.length ~/ 2;
  return sorted.length.isOdd ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
}

void main() {
  const typicalFrontmatter = '''
name: skills-lint-validation
description: >
  Use this skill to execute skills_lint validation and resolve rule violations
  across AI agent skills. Covers running the CLI validator, analyzing diagnostic
  failures, applying automated fixes with --fix, and authoring custom SkillRule
  classes in Dart.
compatibility: Dart 3.12 or later
metadata:
  internal: false
  version: 0.5.3
  tags:
    - lint
    - validation
    - agent-skills
''';

  // Worst-case valid document right at the 10,000-node limit:
  // Root YamlMap (1 node) + 1 key + 1 YamlList (3 nodes so far) + 9,997 scalar items = 10,000 nodes.
  final atNodeLimitItems = List.generate(9997, (i) => '  - item_$i').join('\n');
  final atNodeLimitYaml = 'items:\n$atNodeLimitItems\n';

  // Worst-case flow document right at the 10,000-bracket limit and 10,000-node limit:
  //Wait: 4,999 nested 1-element lists? maxDepth is 64!
  // So a list of 9,998 empty lists `[ [], [], ... ]` has 9,999 `[` brackets (close to 10,000) and 9,999 nodes!
  final atBracketAndNodeLimitYaml =
      'items: [${List.filled(9997, '[]').join(', ')}]\n'; // 1 + 9997 = 9998 `[` brackets, 1(map)+1(key)+1(list)+9997(lists) = 10,000 nodes!

  // Verify both worst-case docs actually pass YamlLimits.load without throwing!
  YamlLimits.loadYaml(atNodeLimitYaml);
  YamlLimits.loadYaml(atBracketAndNodeLimitYaml);

  // Verify adding 1 more item to atNodeLimitYaml throws!
  try {
    YamlLimits.loadYaml('${atNodeLimitYaml}  - extra\n');
    throw StateError('Expected node limit to throw!');
  } on YamlException {
    // Expected.
  }

  double bench(String label, int iterations, Object? Function() fn) {
    // Warmup
    for (var i = 0; i < min(iterations, 500); i++) {
      fn();
    }
    final samples = <double>[];
    final sw = Stopwatch();
    for (var round = 0; round < 15; round++) {
      sw
        ..reset()
        ..start();
      for (var i = 0; i < iterations; i++) {
        fn();
      }
      sw.stop();
      samples.add(sw.elapsedMicroseconds / iterations);
    }
    final med = median(samples);
    stdout.writeln(
      '$label: median ${med.toStringAsFixed(2)} us/op (min ${samples.reduce(min).toStringAsFixed(2)}, max ${samples.reduce(max).toStringAsFixed(2)})',
    );
    return med;
  }

  stdout.writeln('=== Typical SKILL.md frontmatter (${typicalFrontmatter.length} bytes) ===');
  bench('raw loadYaml', 2000, () => loadYaml(typicalFrontmatter));
  bench(
    'YamlAnchorScanner.firstAnchorOrAlias',
    5000,
    () => YamlAnchorScanner.firstAnchorOrAlias(typicalFrontmatter),
  );
  bench('YamlLimits.load', 2000, () => YamlLimits.loadYaml(typicalFrontmatter));
  bench('YamlLimits.loadFrontmatter', 2000, () => YamlLimits.loadFrontmatter(typicalFrontmatter));

  // Isolate _checkSize + bracket count overhead:
  final parsedTypicalNode = loadYamlNode(typicalFrontmatter);
  bench('raw loadYamlNode', 2000, () => loadYamlNode(typicalFrontmatter));
  bench(
    'bracket count on typical',
    10000,
    () => '['.allMatches(typicalFrontmatter).length + '{'.allMatches(typicalFrontmatter).length,
  );
  // Keep parsedTypicalNode alive
  if (parsedTypicalNode.value == null) throw StateError('unexpected');

  stdout.writeln(
    '\n=== Worst-case block YAML at 10,000-node limit (${atNodeLimitYaml.length} bytes) ===',
  );
  bench('raw loadYaml (10k block nodes)', 20, () => loadYaml(atNodeLimitYaml));
  bench(
    'YamlAnchorScanner (10k block nodes)',
    50,
    () => YamlAnchorScanner.firstAnchorOrAlias(atNodeLimitYaml),
  );
  bench('YamlLimits.load (10k block nodes)', 20, () => YamlLimits.loadYaml(atNodeLimitYaml));
  bench(
    'YamlLimits.loadFrontmatter (10k block nodes)',
    20,
    () => YamlLimits.loadFrontmatter(atNodeLimitYaml),
  );

  stdout.writeln(
    '\n=== Worst-case flow YAML at 10,000-node & 9,998-bracket limit (${atBracketAndNodeLimitYaml.length} bytes) ===',
  );
  bench('raw loadYaml (10k flow nodes/brackets)', 20, () => loadYaml(atBracketAndNodeLimitYaml));
  bench(
    'YamlLimits.load (10k flow nodes/brackets)',
    20,
    () => YamlLimits.loadYaml(atBracketAndNodeLimitYaml),
  );

  // Also test billion laughs rejection speed!
  const levels = 'abcdefghi';
  final bl = StringBuffer('name: demo\n');
  for (var i = 0; i < levels.length; i++) {
    final item = i == 0 ? 'x' : '*${levels[i - 1]}';
    bl.writeln('${levels[i]}: &${levels[i]} [${List.filled(10, item).join(', ')}]');
  }
  bl.writeln('description: *i');
  final billionLaughsYaml = bl.toString();

  stdout.writeln(
    '\n=== Rejecting billion-laughs (10^9 expanded nodes, ${billionLaughsYaml.length} bytes) ===',
  );
  bench('YamlLimits.load (rejects at 10,001st expanded node)', 200, () {
    try {
      return YamlLimits.loadYaml(billionLaughsYaml);
    } on YamlException {
      return null;
    }
  });
  bench('YamlLimits.loadFrontmatter (rejects at first anchor)', 5000, () {
    try {
      return YamlLimits.loadFrontmatter(billionLaughsYaml);
    } on YamlException {
      return null;
    }
  });

  // Worst-case 10,000 nested brackets `[` * 10000 + `]` * 10000 (which hits maxDepth=64 after parsing, or test parse cost at 10,000 nested brackets!)
  final nested10kBrackets = '${'[' * 10000}${']' * 10000}';
  stdout.writeln(
    '\n=== Worst-case 10,000 nested `[` brackets (${nested10kBrackets.length} bytes) ===',
  );
  bench('YamlLimits.load on 10,000 nested `[` (parses then rejects at depth 65)', 5, () {
    try {
      return YamlLimits.loadYaml(nested10kBrackets);
    } on YamlException {
      return null;
    }
  });
  final nested10001Brackets = '${'[' * 10001}${']' * 10001}';
  bench('YamlLimits.load on 10,001 nested `[` (rejected pre-parse by bracket count)', 1000, () {
    try {
      return YamlLimits.loadYaml(nested10001Brackets);
    } on YamlException {
      return null;
    }
  });
}
