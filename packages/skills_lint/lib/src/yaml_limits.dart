// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:source_span/source_span.dart';
import 'package:yaml/yaml.dart';

import 'models/skill_context.dart';
import 'yaml_anchor_scanner.dart';

/// Size and structure limits on the YAML that skills_lint reads.
///
/// `package:yaml` shares the node behind each alias, so a few hundred bytes
/// can describe billions of values, and collection mapping keys take
/// exponential time to hash when nested. Code that walks or prints such a
/// value runs out of memory, and deep nesting overflows the stack. `lib/`
/// reads every YAML document through [YamlLimits], so these limits run before
/// any rule or configuration consumer sees the value.
abstract final class YamlLimits {
  /// The largest YAML document, in UTF-8 bytes, that skills_lint parses.
  ///
  /// `package:yaml` builds the whole node tree before [maxNodes] and
  /// [maxDepth] are checked, so the memory a parse takes grows with the size
  /// of the input. This limit rejects a larger document before any scan or
  /// parse, so that memory stays bounded. Real `SKILL.md` frontmatter is a
  /// few kilobytes at most, so this limit leaves room for long `metadata` and
  /// `hooks` blocks.
  static const int maxBytes = 64 * 1024;

  /// The most `[` and `{` characters a YAML document may hold.
  ///
  /// Each flow collection starts with one of them, so this bounds flow
  /// nesting before parsing. `package:yaml` slows down with the square of
  /// that nesting: [maxFlowCollectionStarts] levels take under a second.
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
    _checkByteSize(yaml);
    return _loadWithinByteLimit(yaml, sourceUrl: sourceUrl);
  }

  /// Parses the frontmatter of a `SKILL.md` like [loadYaml], and also throws a
  /// [YamlException] if it holds a YAML anchor or alias.
  ///
  /// The anchor scan reads the text before parsing it, so the error points at
  /// the first anchor or alias even when the document has other problems.
  static Object? loadFrontmatter(String yaml) {
    _checkByteSize(yaml);
    final YamlAnchorToken? found = YamlAnchorScanner.firstAnchorOrAlias(yaml);
    if (found != null) {
      final kind = found.token.startsWith('&') ? 'anchor' : 'alias';
      throw YamlException(
        '`${found.token}` is a YAML $kind. ${SkillContext.skillFileName} frontmatter '
        "doesn't support anchors (`&`) or aliases (`*`). Write the value out in full, or quote it.",
        found.span,
      );
    }
    return _loadWithinByteLimit(yaml);
  }

  /// Parses a `pubspec.yaml` like `Pubspec.parse`, after checking it with
  /// [loadYaml].
  ///
  /// Throws a [YamlException] if the document fails [loadYaml], and whatever
  /// `Pubspec.parse` throws for a pubspec it rejects.
  static Pubspec loadPubspec(String yaml, {Uri? sourceUrl}) {
    loadYaml(yaml, sourceUrl: sourceUrl);
    return Pubspec.parse(yaml, sourceUrl: sourceUrl);
  }

  /// Throws a [YamlException] if [yaml] is more than [maxBytes] long in UTF-8.
  ///
  /// Counts the bytes from the UTF-16 code units without encoding the text,
  /// so the check allocates nothing however large [yaml] is.
  static void _checkByteSize(String yaml) {
    // Each code unit takes at most three UTF-8 bytes, so text of at most a
    // third of maxBytes code units is within the limit without counting.
    if (yaml.length * 3 <= maxBytes) {
      return;
    }
    final int bytes = _utf8Length(yaml);
    if (bytes > maxBytes) {
      throw YamlException(
        'The YAML is ${_formatCount(bytes)} bytes, more than the limit of '
        '${_formatCount(maxBytes)} bytes.',
        null, // There is no single location to point to.
      );
    }
  }

  /// The number of bytes [text] takes in UTF-8.
  static int _utf8Length(String text) {
    var bytes = 0;
    final int length = text.length;
    for (var i = 0; i < length; i++) {
      final int unit = text.codeUnitAt(i);
      if (unit < 0x80) {
        bytes += 1;
      } else if (unit < 0x800) {
        bytes += 2;
      } else if (unit >= 0xD800 && unit < 0xDC00 && i + 1 < length) {
        final int next = text.codeUnitAt(i + 1);
        if (next >= 0xDC00 && next < 0xE000) {
          // A surrogate pair is one code point that takes four bytes.
          bytes += 4;
          i++;
        } else {
          bytes += 3;
        }
      } else {
        // Other BMP code points, and lone surrogates, which UTF-8 encodes
        // as the three-byte replacement character.
        bytes += 3;
      }
    }
    return bytes;
  }

  /// Writes [count] with a comma between each group of three digits.
  static String _formatCount(int count) {
    final digits = count.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  static Object? _loadWithinByteLimit(String yaml, {Uri? sourceUrl}) {
    var flowStarts = 0;
    for (final int unit in yaml.codeUnits) {
      if (unit == 0x5B || unit == 0x7B) {
        flowStarts++;
      }
    }
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
      // overflow cleanly, so report it as nesting over the limit.
      throw YamlException(_tooDeepMessage, null);
    } finally {
      yamlWarningCallback = previousWarning;
    }
  }

  static void _ignoreYamlWarning(String _, [SourceSpan? _]) {}

  /// Walks [root] with each alias expanded, and stops at the first limit it
  /// passes, so the walk visits at most one node past [maxNodes].
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
