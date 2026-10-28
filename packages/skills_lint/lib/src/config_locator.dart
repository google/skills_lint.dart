// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Finds where a rule name appears in a configuration file, after a check
/// has already reported it.
///
/// [Configuration] does not record source locations. Checks that need a line
/// look it up here, only when they have a finding.
library;

import 'dart:io';

import 'package:yaml/yaml.dart';

import 'config_parser.dart';

/// Where a rule name sits in `skills_lint.yaml`.
///
/// `section` is [ConfigParser.rulesKey] for the top-level `rules` map, or
/// [ConfigParser.directoriesKey] or [ConfigParser.individualSkillsKey] for a
/// target entry. `entryIndex` is the position of the target in
/// [Configuration.directoryConfigs] or [Configuration.individualSkillConfigs],
/// and is `null` for the top-level `rules` map.
typedef RuleKeyPath = ({String section, int? entryIndex, String ruleName});

/// The 1-based line of [key] in [configFile], or `null` when it cannot be
/// found for certain.
///
/// Returns `null` when the file cannot be read or parsed, or when the entry
/// at the key's `entryIndex` does not contain the rule name. The parser
/// drops invalid target entries, so the index can point at a different YAML
/// entry; in that case no line is better than a wrong one.
int? lineOfRuleKey(String configFile, RuleKeyPath key) {
  final YamlNode root;
  try {
    root = loadYamlNode(File(configFile).readAsStringSync(), sourceUrl: Uri.file(configFile));
  } on Exception {
    return null;
  }
  final YamlNode? toolConfig = _child(root, ConfigParser.skillsLintKey);
  final YamlNode? rules = switch (key.entryIndex) {
    null => _child(toolConfig, ConfigParser.rulesKey),
    final int index => _child(
      _entry(_child(toolConfig, key.section), index),
      ConfigParser.rulesKey,
    ),
  };
  if (rules is! YamlMap) {
    return null;
  }
  for (final Object? keyNode in rules.nodes.keys) {
    if (keyNode is YamlNode && keyNode.value.toString() == key.ruleName) {
      return keyNode.span.start.line + 1;
    }
  }
  return null;
}

YamlNode? _child(YamlNode? node, String key) => node is YamlMap ? node.nodes[key] : null;

YamlNode? _entry(YamlNode? node, int index) =>
    node is YamlList && index < node.nodes.length ? node.nodes[index] : null;
