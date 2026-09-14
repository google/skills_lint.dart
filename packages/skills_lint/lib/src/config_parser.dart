// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:yaml/yaml.dart';

import 'config_serializer.dart';
import 'models/analysis_severity.dart';
import 'models/check_type.dart';
import 'models/custom_rule_parameters.dart';
import 'models/rule_config.dart';
import 'path_utils.dart';
import 'rule_registry.dart';

final Logger _log = Logger('skills_lint');

class ConfigParser {
  static const String skillsLintKey = 'skills_lint';
  static const String rulesKey = 'rules';
  static const String directoriesKey = 'directories';
  static const String individualSkillsKey = 'individual_skills';
  static const String pathKey = 'path';
  static const String ignoreFileKey = 'ignore_file';
  static const String severityKey = 'severity';

  static const Set<String> _allowedTopLevelKeys = {rulesKey, directoriesKey, individualSkillsKey};
  static const Set<String> _allowedDirectoryKeys = {pathKey, rulesKey, ignoreFileKey};

  static final Map<String, AnalysisSeverity> _severityNameMap = AnalysisSeverity.values.asNameMap();

  static AnalysisSeverity? _parseSeverity(
    Object? value,
    String ruleName,
    String contextLabel,
    List<String> parsingErrors,
  ) {
    if (value == null) {
      return null;
    }
    final valueStr = value.toString();
    final AnalysisSeverity? severity = _severityNameMap[valueStr];
    if (severity != null) {
      return severity;
    }
    parsingErrors.add(
      '$contextLabel: Invalid severity "$valueStr" for rule "$ruleName". Expected one of: ${_severityNameMap.keys.join(', ')}.',
    );
    return null;
  }

  /// Parses configuration settings from raw YAML [content].
  ///
  /// [sourcePath] provides optional file path context for error reporting and diagnostics.
  static Configuration parse(String content, {String? sourcePath}) {
    try {
      final Object? yaml = loadYaml(content);
      return fromYaml(yaml, sourcePath: sourcePath);
    } catch (e) {
      final String source = sourcePath ?? 'content';
      final message = 'Failed to parse $source: $e';
      _log.severe(message);
      return Configuration(parsingErrors: <String>[message]);
    }
  }

  /// Parses a [Configuration] from an already loaded [yaml] object structure.
  ///
  /// [sourcePath] provides optional file path context for error reporting.
  static Configuration fromYaml(Object? yaml, {String? sourcePath}) {
    if (yaml == null) {
      return const Configuration();
    }
    if (yaml is! YamlMap) {
      final message = 'Top-level configuration must be a YAML map, found: ${yaml.runtimeType}.';
      _log.severe(message);
      return Configuration(parsingErrors: <String>[message]);
    }
    if (yaml.containsKey(skillsLintKey)) {
      final Object? toolConfig = yaml[skillsLintKey];
      if (toolConfig is! YamlMap) {
        final message =
            'Expected "$skillsLintKey" to be a YAML map, found: ${toolConfig.runtimeType}.';
        _log.severe(message);
        return Configuration(parsingErrors: <String>[message]);
      }
      final parsingErrors = <String>[];

      _validateTopLevelKeys(toolConfig, parsingErrors);
      final Map<String, RuleConfigPatch> rulesResult = _parseDefaultRules(
        toolConfig,
        parsingErrors,
      );
      final List<LintTargetConfig> directoryConfigs = _parseConfigList(
        toolConfig,
        directoriesKey,
        parsingErrors,
      );
      final List<LintTargetConfig> individualSkillConfigs = _parseConfigList(
        toolConfig,
        individualSkillsKey,
        parsingErrors,
      );

      return Configuration(
        directoryConfigs: directoryConfigs,
        individualSkillConfigs: individualSkillConfigs,
        ruleConfigs: rulesResult,
        parsingErrors: parsingErrors,
      );
    }
    return const Configuration();
  }

  /// Loads the configuration from the specified [path], or from the default
  /// `skills_lint.yaml` relative to the current working directory if no path is provided.
  ///
  /// If an explicit [path] is provided and the file does not exist, this method throws
  /// a [FileSystemException]. If no path is provided and the default `skills_lint.yaml`
  /// file does not exist in the current working directory, an empty [Configuration] is returned.
  static Future<Configuration> loadConfig({String? path}) async {
    final String resolvedPath = expandPath(path ?? 'skills_lint.yaml');
    final configFile = File(resolvedPath);

    if (!configFile.existsSync()) {
      if (path != null) {
        throw FileSystemException('Configuration file not found', resolvedPath);
      }
      return const Configuration();
    }

    try {
      final String content = await configFile.readAsString();
      return parse(content, sourcePath: resolvedPath);
    } catch (e) {
      if (e is FileSystemException) {
        rethrow;
      }
      final message = 'Failed to parse $resolvedPath: $e';
      _log.severe(message);
      return Configuration(parsingErrors: <String>[message]);
    }
  }

  /// Validates that all keys at the top level of the `skills_lint` configuration map are recognized.
  /// Appends error messages to `parsingErrors` for any unrecognized keys.
  static void _validateTopLevelKeys(YamlMap toolConfig, List<String> parsingErrors) {
    for (final Object? key in toolConfig.keys) {
      final keyStr = key.toString();
      if (!_allowedTopLevelKeys.contains(keyStr)) {
        parsingErrors.add('Unrecognized top-level key "$keyStr" in skills_lint configuration.');
      }
    }
  }

  /// Parses the project-wide default rule configurations from the top-level `rules` map.
  ///
  /// The settings parsed here serve as the global defaults that apply to all
  /// validated skills in the project. Any target-specific settings defined
  /// under `directories` or `individual_skills` will override these global defaults.
  ///
  /// Extracts both default severities and parameters, appending any parameter type or key
  /// validation errors to [parsingErrors].
  static Map<String, RuleConfigPatch> _parseDefaultRules(
    YamlMap toolConfig,
    List<String> parsingErrors,
  ) {
    if (toolConfig.containsKey(rulesKey)) {
      final Object? rules = toolConfig[rulesKey];
      if (rules is YamlMap) {
        return _parseRulesMap(rules, parsingErrors, 'Global rules');
      }
    }
    return const <String, RuleConfigPatch>{};
  }

  /// Iterates a YAML rules map and converts each entry into a [RuleConfigPatch].
  ///
  /// Validates that parameter keys and value types match their definitions in the registry,
  /// appending any validation errors to [parsingErrors] labeled by [contextLabel].
  static Map<String, RuleConfigPatch> _parseRulesMap(
    YamlMap rulesMap,
    List<String> parsingErrors,
    String contextLabel,
  ) {
    final ruleConfigs = <String, RuleConfigPatch>{};

    for (final Object? key in rulesMap.keys) {
      final ruleName = key.toString();
      final Object? value = rulesMap[key];

      // Rules must have a unique name so we can assume one match.
      final Iterable<CheckType> checkMatches = RuleRegistry.allChecks.where(
        (CheckType c) => c.name == ruleName,
      );
      final CheckType? check = checkMatches.isEmpty ? null : checkMatches.first;

      ruleConfigs[ruleName] = _parseRuleConfigPatch(
        value,
        ruleName,
        check,
        parsingErrors,
        contextLabel,
      );
    }

    return ruleConfigs;
  }

  /// Parses a single rule's configuration value into a [RuleConfigPatch].
  ///
  /// Supports simple scalar severity declarations (e.g., `rule-name: error`) as
  /// well as map declarations containing custom parameter overrides and severity
  /// settings (e.g., `rule-name: { severity: error, param: value }`). Validates
  /// any custom parameters against [check], appending schema validation errors
  /// to [parsingErrors] labeled with [contextLabel].
  static RuleConfigPatch _parseRuleConfigPatch(
    Object? value,
    String ruleName,
    CheckType? check,
    List<String> parsingErrors,
    String contextLabel,
  ) {
    if (value is! YamlMap) {
      final AnalysisSeverity? severity = _parseSeverity(
        value,
        ruleName,
        contextLabel,
        parsingErrors,
      );
      return RuleConfigPatch(severity: severity);
    }

    final AnalysisSeverity? severity = value.containsKey(severityKey)
        ? _parseSeverity(value[severityKey], ruleName, contextLabel, parsingErrors)
        : null;

    final parameters = <String, Object?>{};
    for (final Object? paramKey in value.keys) {
      final paramName = paramKey.toString();
      if (paramName != severityKey) {
        parameters[paramName] = value[paramKey];
      }
    }

    final CustomRuleParameters? customParams = parameters.isNotEmpty
        ? CustomRuleParameters(parameters)
        : null;

    if (customParams != null && check != null) {
      final List<String> errors = check.validateParameters(customParams);
      for (final error in errors) {
        parsingErrors.add('$contextLabel: $error');
      }
    }

    return RuleConfigPatch(severity: severity, parameters: customParams);
  }

  /// Iterates a top-level YAML target list (`directories` or `individual_skills`)
  /// and parses each element into a [LintTargetConfig].
  ///
  /// Delegates validation of an individual list element to [_parseTargetEntry].
  /// Returns an empty list if [configKey] is omitted or not a list.
  static List<LintTargetConfig> _parseConfigList(
    YamlMap toolConfig,
    String configKey,
    List<String> parsingErrors,
  ) {
    if (!toolConfig.containsKey(configKey)) {
      return const <LintTargetConfig>[];
    }
    final Object? items = toolConfig[configKey];
    if (items is! YamlList) {
      return const <LintTargetConfig>[];
    }

    final entryLabelCap = configKey == directoriesKey
        ? 'Directory entry'
        : 'Individual skill entry';
    final entryLabelLower = configKey == directoriesKey
        ? 'directory entry'
        : 'individual skill entry';

    final configs = <LintTargetConfig>[];
    for (final Object? dir in items) {
      if (dir is! YamlMap || !dir.containsKey(pathKey)) {
        continue;
      }
      final LintTargetConfig? config = _parseTargetEntry(
        dir,
        entryLabelCap,
        entryLabelLower,
        parsingErrors,
      );
      if (config != null) {
        configs.add(config);
      }
    }
    return configs;
  }

  /// Parses a single dictionary element from a target list (`directories` or `individual_skills`).
  ///
  /// Validates the `path` string and checks for unrecognized keys. Delegates
  /// parsing of sub-keys to [_parseLocalRulesForTarget] (`rules`) and
  /// [_parseIgnoreFileForTarget] (`ignore_file`). Returns `null` if `path` is
  /// invalid or missing.
  static LintTargetConfig? _parseTargetEntry(
    YamlMap dir,
    String entryLabelCap,
    String entryLabelLower,
    List<String> parsingErrors,
  ) {
    final Object? pathValue = dir[pathKey];
    if (pathValue is! String) {
      parsingErrors.add(
        '$entryLabelCap "$pathKey" must be a string; got "$pathValue" '
        '(${pathValue.runtimeType}). Skipping entry.',
      );
      return null;
    }
    final String path = pathValue;

    for (final Object? key in dir.keys) {
      final keyStr = key.toString();
      if (!_allowedDirectoryKeys.contains(keyStr)) {
        parsingErrors.add('Unrecognized key "$keyStr" in $entryLabelLower for "$path".');
      }
    }

    final Map<String, RuleConfigPatch> ruleConfigs = _parseLocalRulesForTarget(
      dir,
      path,
      entryLabelCap,
      parsingErrors,
    );

    final String? ignoreFile = _parseIgnoreFileForTarget(dir, path, entryLabelCap, parsingErrors);

    return LintTargetConfig(path: path, ruleConfigs: ruleConfigs, ignoreFile: ignoreFile);
  }

  /// Parses path-specific rule overrides under a target entry's `rules` key.
  ///
  /// Unlike [_parseDefaultRules], which sets global baselines, configurations
  /// parsed here apply only to skills within this specific target path.
  /// Delegates to [_parseRulesMap].
  static Map<String, RuleConfigPatch> _parseLocalRulesForTarget(
    YamlMap dir,
    String path,
    String entryLabelCap,
    List<String> parsingErrors,
  ) {
    if (!dir.containsKey(rulesKey)) {
      return const <String, RuleConfigPatch>{};
    }
    final Object? localRules = dir[rulesKey];
    if (localRules is YamlMap) {
      return _parseRulesMap(localRules, parsingErrors, '$entryLabelCap rules for "$path"');
    }
    parsingErrors.add(
      '$entryLabelCap "$rulesKey" for "$path" must be a map; '
      'got "$localRules" (${localRules.runtimeType}). Ignoring local rules.',
    );
    return const <String, RuleConfigPatch>{};
  }

  /// Parses the custom ignore file path under a target entry's `ignore_file` key.
  ///
  /// Returns `null` if omitted. If present but not a string, appends a type
  /// error to [parsingErrors] and returns `null` to fall back to the default
  /// ignore file.
  static String? _parseIgnoreFileForTarget(
    YamlMap dir,
    String path,
    String entryLabelCap,
    List<String> parsingErrors,
  ) {
    if (!dir.containsKey(ignoreFileKey)) {
      return null;
    }
    final Object? ignoreFileValue = dir[ignoreFileKey];
    if (ignoreFileValue is String) {
      return ignoreFileValue;
    }
    if (ignoreFileValue != null) {
      parsingErrors.add(
        '$entryLabelCap "$ignoreFileKey" for "$path" must be a string; '
        'got "$ignoreFileValue" (${ignoreFileValue.runtimeType}). '
        'Falling back to the default ignore file.',
      );
    }
    return null;
  }
}

/// Configuration for a specific directory containing skills, or an individual skill.
///
/// Allows overriding rules and specifying a custom ignore file for skills
/// located within or at this path.
@immutable
class LintTargetConfig {
  const LintTargetConfig({
    required this.path,
    this.ruleConfigs = const <String, RuleConfigPatch>{},
    this.ignoreFile,
  });

  /// The path to the directory containing skills.
  ///
  /// Can be absolute or relative to the current working directory.
  /// Supports tilde expansion (e.g., `~/...`).
  final String path;
  final Map<String, RuleConfigPatch> ruleConfigs;
  final String? ignoreFile;

  /// Converts this target configuration into its YAML map representation.
  Map<String, Object?> toYamlMap() => ConfigSerializer.targetConfigToYamlMap(this);

  /// Converts this target configuration into a formatted YAML string.
  String toYamlString() => ConfigSerializer.targetConfigToYamlString(this);

  // TODO(reidbaker): https://github.com/google/skills_lint.dart/issues/179
  @Deprecated('Use ruleConfigs instead')
  Map<String, AnalysisSeverity> get rules {
    final resolvedSeverities = <String, AnalysisSeverity>{};
    for (final MapEntry<String, RuleConfigPatch> entry in ruleConfigs.entries) {
      final AnalysisSeverity? severity = entry.value.severity;
      if (severity != null) {
        resolvedSeverities[entry.key] = severity;
      }
    }
    return resolvedSeverities;
  }
}

/// Structured configuration for the linter.
@immutable
class Configuration {
  const Configuration({
    this.directoryConfigs = const <LintTargetConfig>[],
    this.individualSkillConfigs = const <LintTargetConfig>[],
    this.ruleConfigs = const <String, RuleConfigPatch>{},
    this.parsingErrors = const <String>[],
  });
  final List<LintTargetConfig> directoryConfigs;
  final List<LintTargetConfig> individualSkillConfigs;
  final Map<String, RuleConfigPatch> ruleConfigs;
  final List<String> parsingErrors;

  /// Converts this configuration into its YAML map representation.
  Map<String, Object?> toYamlMap() => ConfigSerializer.configToYamlMap(this);

  /// Converts this configuration into a formatted YAML string.
  String toYamlString() => ConfigSerializer.configToYamlString(this);

  // TODO(reidbaker): https://github.com/google/skills_lint.dart/issues/179
  @Deprecated('Use ruleConfigs instead')
  Map<String, AnalysisSeverity> get configuredRules {
    final resolvedSeverities = <String, AnalysisSeverity>{};
    for (final MapEntry<String, RuleConfigPatch> entry in ruleConfigs.entries) {
      final AnalysisSeverity? severity = entry.value.severity;
      if (severity != null) {
        resolvedSeverities[entry.key] = severity;
      }
    }
    return resolvedSeverities;
  }
}
