// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Finds configured rule names that match no known rule.
library;

import 'dart:io';

import 'package:yaml/yaml.dart';

import 'config_parser.dart';
import 'models/rule_config.dart';
import 'suggestions/closest_name.dart';
import 'suggestions/did_you_mean.dart';

/// Describes each rule name in [config] and [overrides] that is not in
/// [knownNames], in the same form as [Configuration.parsingErrors], so
/// callers report them as misconfigured keys.
///
/// [ConfigParser] cannot do this check, because it does not know which custom
/// rules the caller passes. Call it where the full set of rule names is known.
///
/// Checks the top-level `rules` map, the `rules` map of every `directories`
/// and `individual_skills` entry, then the keys of [overrides] (the
/// `resolvedRuleConfigs` of the API).
///
/// Each message names the unknown rule, where it is in the configuration, and
/// the closest known names. It shows the file and line when the configuration
/// came from a file: [configFile] when given, or else the file a parsed target
/// was declared in. Otherwise it shows no file.
List<String> unknownRuleNameErrors(
  Configuration config, {
  required Iterable<String> knownNames,
  Map<String, RuleConfigPatch> overrides = const {},
  String? configFile,
}) {
  final List<String> known = knownNames.toList();
  final Set<String> knownSet = known.toSet();
  final String? file = configFile ?? _declaredFile(config);
  final YamlNode? root = file == null ? null : _load(file);

  String message(String name, String where, YamlMap? rulesNode) {
    final int? line = _lineOfKey(rulesNode, name);
    final location = line == null ? '' : ' ($file:$line)';
    final List<String> suggestions = closestNames(name, known, maxDistance: thirdOfLength(name));
    final hint = suggestions.isEmpty ? '' : ' ${didYouMean(suggestions)}';
    return 'Unknown rule "$name" in $where$location.$hint';
  }

  Iterable<String> check(Map<String, RuleConfigPatch> rules, String where, YamlMap? rulesNode) => [
    for (final String name in rules.keys)
      if (!knownSet.contains(name)) message(name, where, rulesNode),
  ];

  final YamlNode? toolConfig = _child(root, ConfigParser.skillsLintKey);
  return [
    ...check(config.ruleConfigs, ConfigParser.rulesKey, _rulesOf(toolConfig)),
    for (final (String section, List<LintTargetConfig> targets) in [
      (ConfigParser.directoriesKey, config.directoryConfigs),
      (ConfigParser.individualSkillsKey, config.individualSkillConfigs),
    ])
      for (final LintTargetConfig target in targets)
        ...check(
          target.ruleConfigs,
          '$section["${declarationOf(target)?.declaredPath ?? target.path}"].${ConfigParser.rulesKey}',
          _rulesOf(_targetNode(_child(toolConfig, section), target)),
        ),
    ...check(overrides, 'resolvedRuleConfigs', null),
  ];
}

/// The file any target of [config] was declared in, or `null`.
String? _declaredFile(Configuration config) {
  for (final LintTargetConfig target in [
    ...config.directoryConfigs,
    ...config.individualSkillConfigs,
  ]) {
    final String? file = declarationOf(target)?.source?.file;
    if (file != null) {
      return file;
    }
  }
  return null;
}

/// Parses [file] again, or returns `null` if it cannot be read or parsed.
YamlNode? _load(String file) {
  try {
    return loadYamlNode(File(file).readAsStringSync(), sourceUrl: Uri.file(file));
  } on Exception {
    return null;
  }
}

YamlNode? _child(YamlNode? node, String key) => node is YamlMap ? node.nodes[key] : null;

YamlMap? _rulesOf(YamlNode? node) => switch (_child(node, ConfigParser.rulesKey)) {
  final YamlMap rules => rules,
  _ => null,
};

/// The entry of the target list [list] that [target] was parsed from, found
/// by the line its `path` key is on.
YamlNode? _targetNode(YamlNode? list, LintTargetConfig target) {
  final int? line = declarationOf(target)?.source?.line;
  if (list is! YamlList || line == null) {
    return null;
  }
  for (final YamlNode entry in list.nodes) {
    if (entry is YamlMap) {
      for (final Object? key in entry.nodes.keys) {
        if (key is YamlNode &&
            key.value == ConfigParser.pathKey &&
            key.span.start.line + 1 == line) {
          return entry;
        }
      }
    }
  }
  return null;
}

/// The 1-based line of [key] in [rules], or `null`.
int? _lineOfKey(YamlMap? rules, String key) {
  for (final Object? node in rules?.nodes.keys ?? const <Object?>[]) {
    if (node is YamlNode && node.value.toString() == key) {
      return node.span.start.line + 1;
    }
  }
  return null;
}
