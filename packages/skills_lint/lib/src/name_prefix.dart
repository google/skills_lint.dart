// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:source_span/source_span.dart';
import 'package:yaml/yaml.dart';

import 'models/skill_context.dart';
import 'path_utils.dart';

/// Whether [skillName] is [prefix] or starts with [prefix] followed by a
/// hyphen.
bool hasNamePrefix(String skillName, String prefix) =>
    skillName == prefix || skillName.startsWith('$prefix-');

/// A valid skill name that starts with [prefix] and keeps the rest of
/// [currentName].
///
/// Both names are split into lowercase words. If the words of [prefix]
/// appear in [currentName], the words after them are kept, or the words
/// before them when nothing follows.
///
/// Examples:
/// * `suggestPrefixedName(currentName: 'setup', prefix: 'skills_lint')` -> `'skills-lint-setup'`
/// * `suggestPrefixedName(currentName: 'dart-skills-lint-setup', prefix: 'skills_lint')` -> `'skills-lint-setup'`
/// * `suggestPrefixedName(currentName: 'skills_lint_setup', prefix: 'skills_lint')` -> `'skills-lint-setup'`
/// * `suggestPrefixedName(currentName: 'skills_lint', prefix: 'skills_lint')` -> `'skills-lint'`
String suggestPrefixedName({required String currentName, required String prefix}) {
  final List<String> prefixTokens = _tokenize(prefix);
  final List<String> skillTokens = _tokenize(currentName);

  if (prefixTokens.isEmpty) {
    return normalizeSkillNameToken(currentName);
  }

  var matchStart = -1;
  for (var i = 0; i <= skillTokens.length - prefixTokens.length; i++) {
    var match = true;
    for (var j = 0; j < prefixTokens.length; j++) {
      if (skillTokens[i + j] != prefixTokens[j]) {
        match = false;
        break;
      }
    }
    if (match) {
      matchStart = i;
      break;
    }
  }

  final List<String> suffixTokens;
  if (matchStart >= 0) {
    final int matchEnd = matchStart + prefixTokens.length;
    final List<String> after = skillTokens.sublist(matchEnd);
    final List<String> before = skillTokens.sublist(0, matchStart);
    suffixTokens = after.isNotEmpty ? after : before;
  } else {
    suffixTokens = skillTokens;
  }

  final resultTokens = [...prefixTokens, ...suffixTokens];
  final String candidate = resultTokens.join('-');
  return normalizeSkillNameToken(candidate);
}

List<String> _tokenize(String input) =>
    input.toLowerCase().split(RegExp(r'[^a-z0-9]+')).where((token) => token.isNotEmpty).toList();

/// [rawContent] with the frontmatter `name` replaced by what [rename] returns
/// for the current name.
///
/// [rename] receives the trimmed name and returns `null` to keep it.
/// [rawContent] is returned unchanged when the frontmatter doesn't parse to a
/// map or `name` isn't a non-empty scalar.
String renameSkillInFrontmatter(String rawContent, String? Function(String currentName) rename) {
  final RegExpMatch? match = SkillContext.skillStartRegex.firstMatch(rawContent);
  if (match == null) {
    return rawContent;
  }
  final String yamlStr = match.group(1)!;

  final Object? yamlObj;
  try {
    yamlObj = loadYaml(yamlStr);
  } on YamlException {
    return rawContent;
  }

  if (yamlObj is! YamlMap) {
    return rawContent;
  }

  final YamlNode? nameNode = yamlObj.nodes['name'];
  if (nameNode == null ||
      nameNode is! YamlScalar ||
      nameNode.value == null ||
      nameNode.value.toString().trim().isEmpty) {
    return rawContent;
  }

  final String? newName = rename(nameNode.value.toString().trim());
  if (newName == null) {
    return rawContent;
  }

  final int yamlOffset = rawContent.indexOf(yamlStr, match.start);
  final SourceSpan span = nameNode.span;
  final String before = rawContent.substring(0, yamlOffset + span.start.offset);
  final String after = rawContent.substring(yamlOffset + span.end.offset);

  return '$before$newName$after';
}
