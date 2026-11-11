// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:source_span/source_span.dart';
import 'package:yaml/yaml.dart';

import 'models/skill_context.dart';
import 'yaml_anchor_scanner.dart';

/// Size and structure limits on the YAML that skills_lint reads.
///
/// `package:yaml` shares the node behind each alias, so a few hundred bytes
/// can describe billions of values, and collection mapping keys take
/// exponential time to hash when nested. Code that walks or prints such a
/// value runs out of memory, and deep nesting overflows the stack. Every YAML
/// parse in `lib/` goes through [YamlLimits] so these limits run before any
/// rule or configuration consumer sees the value.
abstract final class YamlLimits {
  /// The most `[` and `{` characters a YAML document may hold.
  ///
  /// Each flow collection starts with one of them, so this bounds flow
  /// nesting before parsing. `package:yaml` slows down with the square of
  /// that nesting: 10,000 levels take under a second.
  static const int maxFlowCollectionStarts = 10000;

  /// The most nodes a parsed document may hold, counting each alias as a full
  /// copy of the node it refers to.
  static const int maxNodes = 10000;

  /// The deepest nesting of collections a parsed document may hold.
  static const int maxDepth = 64;

  /// Parses [yaml] like `package:yaml`'s `loadYaml`, and throws a
  /// [YamlException] if the document exceeds a size limit or uses an explicit
  /// (`?`), alias or collection mapping key.
  ///
  /// Anchors and aliases used as values are allowed, and count toward
  /// [maxNodes] once expanded.
  static Object? loadYaml(String yaml, {Uri? sourceUrl}) {
    final int flowStarts = '['.allMatches(yaml).length + '{'.allMatches(yaml).length;
    if (flowStarts > maxFlowCollectionStarts) {
      throw YamlException(
        'The YAML has $flowStarts "[" and "{" characters, more than the limit of '
        '$maxFlowCollectionStarts.',
        null, // There is no single location to point to.
      );
    }
    final SourceSpan? complexKey = YamlAnchorScanner.firstComplexKey(yaml);
    if (complexKey != null) {
      throw YamlException(_complexKeyMessage, complexKey);
    }
    final YamlNode root = _parseNodeQuietly(yaml, sourceUrl: sourceUrl);
    _checkSize(root);
    return root.value;
  }

  /// Parses the frontmatter of a `SKILL.md` like [loadYaml], and also throws a
  /// [YamlException] if it holds a YAML anchor or alias.
  ///
  /// The anchor scan reads the text before parsing it, so the error points at
  /// the first anchor or alias even when the document has other problems.
  static Object? loadFrontmatter(String yaml) {
    final YamlAnchorToken? found = YamlAnchorScanner.firstAnchorOrAlias(yaml);
    if (found != null) {
      final kind = found.token.startsWith('&') ? 'anchor' : 'alias';
      throw YamlException(
        '`${found.token}` is a YAML $kind. ${SkillContext.skillFileName} frontmatter '
        "doesn't support anchors (`&`) or aliases (`*`). Write the value out in full, or quote it.",
        found.span,
      );
    }
    return loadYaml(yaml);
  }

  static const String _tooDeepMessage = 'The YAML nests more than $maxDepth levels deep.';

  static const String _complexKeyMessage =
      'Mapping keys must be plain or quoted scalars; explicit (`?`), alias and '
      'collection mapping keys are not supported.';

  static YamlNode _parseNodeQuietly(String yaml, {Uri? sourceUrl}) {
    final YamlWarningCallback previousWarning = yamlWarningCallback;
    // `package:yaml`'s default warning callback calls `print`, which writes
    // unknown-directive warnings straight to stdout and corrupts `--format=json`
    // and `--format=sarif` output.
    yamlWarningCallback = _ignoreYamlWarning;
    try {
      return loadYamlNode(yaml, sourceUrl: sourceUrl);
    } on StackOverflowError {
      // Block nesting such as `- - - x` has no cheap bound before parsing,
      // and the parser recurses once per level. The VM unwinds a stack
      // overflow cleanly, so treat it as nesting over the limit.
      throw YamlException(_tooDeepMessage, null);
    } finally {
      yamlWarningCallback = previousWarning;
    }
  }

  static void _ignoreYamlWarning(String _, [SourceSpan? _]) {}

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
        YamlMap(:final Map<dynamic, YamlNode> nodes) => _mapChildren(nodes),
        YamlList(:final List<YamlNode> nodes) => nodes,
        _ => const [],
      };
      for (final child in children) {
        visit(child, depth + 1);
      }
    }

    visit(root, 0);
  }

  static List<YamlNode> _mapChildren(Map<dynamic, YamlNode> nodes) {
    final children = <YamlNode>[];
    for (final MapEntry<dynamic, YamlNode> entry in nodes.entries) {
      if (entry.key case final YamlNode key) {
        if (key is! YamlScalar) {
          throw YamlException(_complexKeyMessage, key.span);
        }
        children.add(key);
      }
      children.add(entry.value);
    }
    return children;
  }
}
