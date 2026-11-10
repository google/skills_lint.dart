// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:yaml/yaml.dart';

/// Size limits on the files and YAML that skills_lint reads.
///
/// `package:yaml` shares the node behind each alias, so a few hundred bytes
/// can describe billions of values. Code that walks or prints such a value
/// runs out of memory, and deep nesting overflows the stack. These limits
/// stop both before any rule sees the value. Each one is far above what a
/// real `SKILL.md` or `skills_lint.yaml` uses.
abstract final class YamlLimits {
  /// The largest `SKILL.md` that skills_lint reads, in bytes: 1 MiB.
  static const int maxSkillFileBytes = 1024 * 1024;

  /// The most `[` and `{` characters a YAML document may hold.
  ///
  /// Each flow collection starts with one of them, so this bounds flow
  /// nesting before parsing. `package:yaml` slows down with the square of
  /// that nesting: 10,000 levels take about a quarter of a second.
  static const int maxFlowCollectionStarts = 10000;

  /// The most nodes a parsed document may hold, counting each alias as a full
  /// copy of the node it refers to.
  static const int maxNodes = 10000;

  /// The deepest nesting of collections a parsed document may hold.
  static const int maxDepth = 64;

  /// Parses [yaml] like [loadYaml], and throws a [YamlException] if the
  /// document is over any of these limits.
  ///
  /// The checks run before anything expands an alias, so a document over the
  /// limits costs about as much to reject as its size in bytes.
  static Object? load(String yaml) {
    final int flowStarts = '['.allMatches(yaml).length + '{'.allMatches(yaml).length;
    if (flowStarts > maxFlowCollectionStarts) {
      throw YamlException(
        'The YAML has $flowStarts "[" and "{" characters, more than the limit of '
        '$maxFlowCollectionStarts.',
        null, // There is no single location to point to.
      );
    }
    final YamlNode root;
    try {
      root = loadYamlNode(yaml);
    } on StackOverflowError {
      // Block nesting such as `- - - x` has no cheap bound before parsing,
      // and the parser recurses once per level. The VM unwinds a stack
      // overflow cleanly, so treat it as nesting over the limit.
      throw YamlException(_tooDeepMessage, null);
    }
    _checkSize(root);
    return root.value;
  }

  static const String _tooDeepMessage = 'The YAML nests more than $maxDepth levels deep.';

  /// Walks [root] with each alias expanded, and stops at the first limit it
  /// passes, so the walk visits at most [maxNodes] nodes.
  static void _checkSize(YamlNode root) {
    var nodes = 0;
    void visit(YamlNode node, int depth) {
      if (depth > maxDepth) {
        throw YamlException(_tooDeepMessage, node.span);
      }
      nodes++;
      if (nodes > maxNodes) {
        throw YamlException(
          'The YAML holds more than $maxNodes values once aliases are expanded.',
          node.span,
        );
      }
      final Iterable<YamlNode> children = switch (node) {
        YamlMap(:final Map<dynamic, YamlNode> nodes) => [
          for (final MapEntry<dynamic, YamlNode> entry in nodes.entries) ...[
            if (entry.key case final YamlNode key) key,
            entry.value,
          ],
        ],
        YamlList(:final List<YamlNode> nodes) => nodes,
        _ => const [],
      };
      for (final child in children) {
        visit(child, depth + 1);
      }
    }

    visit(root, 0);
  }
}
