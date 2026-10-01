// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'config_serializer.dart';
import 'config_source.dart';
import 'models/analysis_severity.dart';
import 'models/check_type.dart';
import 'models/custom_rule_parameters.dart';
import 'models/rule_config.dart';
import 'models/target_declaration.dart';
import 'path_utils.dart';
import 'rule_registry.dart';

final Logger _log = Logger('skills_lint');

/// Parses and loads YAML configuration for skills_lint.
///
/// Target paths (`directories`, `individual_skills`) and `ignore_file` paths
/// are resolved as the file is read, against the directory holding that file.
/// A configuration therefore selects the same skills no matter which directory
/// the process runs in, which is what lets a subpackage declare
/// `../../.agents/skills` and lets one configuration at the repository root
/// serve every package under it.
///
/// Serializing a configuration that came from a file reproduces the paths as
/// the author typed them, so a tool that reads, edits, and writes a
/// configuration does not replace portable relative paths with absolute ones.
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
    final AnalysisSeverity? severity = _severityNameMap[value.toString()];
    if (severity != null) {
      return severity;
    }
    parsingErrors.add(
      '$contextLabel: Invalid severity "$value" for rule "$ruleName". Expected one of: ${_severityNameMap.keys.join(', ')}.',
    );
    return null;
  }

  /// Parses configuration settings from raw YAML [content].
  ///
  /// [configSource] identifies either the file containing [content] or the
  /// directory used to resolve paths in content without a backing file.
  ///
  /// Callers that supply no source anchor paths to [Directory.current].
  /// Without [configSource], callers can supply both deprecated [sourcePath] and
  /// [baseDirectory]: [baseDirectory] sets the anchor and [sourcePath] labels diagnostics.
  /// Throws [ArgumentError] if [configSource] is combined with either deprecated argument.
  // TODO(Vaishnavi220506): Remove sourcePath and baseDirectory in 0.6.0.
  // https://github.com/google/skills_lint.dart/issues/71
  static Configuration parse(
    String content, {
    ConfigSource? configSource,
    @Deprecated('Use configSource: ConfigSource.file(path)') String? sourcePath,
    @Deprecated('Use configSource: ConfigSource.directory(path)') String? baseDirectory,
  }) {
    _checkSourceArguments(configSource, sourcePath, baseDirectory);
    try {
      final Object? yaml = loadYaml(content);
      return fromYaml(
        yaml,
        configSource: configSource,
        sourcePath: sourcePath,
        baseDirectory: baseDirectory,
      );
    } on YamlException catch (e) {
      final String source = configSource?.filePath ?? sourcePath ?? 'content';
      final message = 'Failed to parse $source: $e';
      _log.severe(message);
      return Configuration(parsingErrors: <String>[message]);
    }
  }

  /// Parses a [Configuration] from an already loaded [yaml] object structure.
  ///
  /// Use this when the YAML is already decoded, such as a configuration nested
  /// inside a larger document. [parse] handles raw text.
  ///
  /// Target paths and ignore files resolve from [configSource], or from
  /// [Directory.current] when no source is supplied.
  /// Without [configSource], callers can supply both deprecated [sourcePath] and
  /// [baseDirectory]: [baseDirectory] sets the anchor and [sourcePath] labels diagnostics.
  /// Throws [ArgumentError] if [configSource] is combined with either deprecated argument.
  static Configuration fromYaml(
    Object? yaml, {
    ConfigSource? configSource,
    @Deprecated('Use configSource: ConfigSource.file(path)') String? sourcePath,
    @Deprecated('Use configSource: ConfigSource.directory(path)') String? baseDirectory,
  }) {
    _checkSourceArguments(configSource, sourcePath, baseDirectory);
    final String? filePath = configSource?.filePath ?? sourcePath;
    final String? directory = configSource?.directoryPath ?? baseDirectory;
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
      // The directory source anchors paths inside the configuration. A relative
      // file source resolves against the working directory, as loadConfig does.
      final String? sourceFile = filePath == null
          ? null
          : canonicalizePath(filePath, baseDirectory: Directory.current.path);
      final String anchor = _resolveAnchorDirectory(
        sourceFile: sourceFile,
        baseDirectory: directory,
      );

      _validateTopLevelKeys(toolConfig, parsingErrors);
      final Map<String, RuleConfigPatch> rulesResult = _parseDefaultRules(
        toolConfig,
        parsingErrors,
      );
      final List<LintTargetConfig> directoryConfigs = _parseConfigList(
        toolConfig,
        directoriesKey,
        parsingErrors,
        anchor,
        sourceFile,
      );
      final List<LintTargetConfig> individualSkillConfigs = _parseConfigList(
        toolConfig,
        individualSkillsKey,
        parsingErrors,
        anchor,
        sourceFile,
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

  static void _checkSourceArguments(
    ConfigSource? configSource,
    String? sourcePath,
    String? baseDirectory,
  ) {
    if (configSource != null && (sourcePath != null || baseDirectory != null)) {
      throw ArgumentError('configSource cannot be combined with sourcePath or baseDirectory');
    }
  }

  /// Returns the absolute directory that target paths and ignore files resolve
  /// against.
  ///
  /// Uses [baseDirectory] when supplied, otherwise the directory holding
  /// [sourceFile], otherwise [Directory.current].
  ///
  /// [sourceFile] is the configuration file, already canonicalized.
  static String _resolveAnchorDirectory({String? sourceFile, String? baseDirectory}) {
    final String cwd = Directory.current.path;
    if (baseDirectory != null) {
      return canonicalizePath(baseDirectory, baseDirectory: cwd);
    }
    if (sourceFile != null) {
      return p.dirname(sourceFile);
    }
    return p.normalize(p.absolute(cwd));
  }

  /// Loads the configuration from the specified [path], or from the default
  /// `skills_lint.yaml` relative to the current working directory if no path is provided.
  ///
  /// Target paths and ignore files in the returned [Configuration] are anchored
  /// to the directory that contains the loaded configuration file.
  ///
  /// If an explicit [path] is provided and the file does not exist, this method throws
  /// a [FileSystemException]. If no path is provided and the default `skills_lint.yaml`
  /// file does not exist in the current working directory, an empty [Configuration] is returned.
  static Future<Configuration> loadConfig({String? path}) async {
    final String resolvedPath = canonicalizePath(
      path ?? 'skills_lint.yaml',
      baseDirectory: Directory.current.path,
    );
    final configFile = File(resolvedPath);

    if (!configFile.existsSync()) {
      if (path != null) {
        throw FileSystemException('Configuration file not found', resolvedPath);
      }
      return const Configuration();
    }

    try {
      final String content = await configFile.readAsString();
      return parse(content, configSource: ConfigSource.file(resolvedPath));
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

    final AnalysisSeverity? severity = _parseSeverity(
      value[severityKey],
      ruleName,
      contextLabel,
      parsingErrors,
    );

    final parameters = <String, Object?>{
      for (final Object? key in value.keys)
        if (key.toString() != severityKey) key.toString(): value[key],
    };

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
  /// Every parsed path is anchored to [anchorDirectory] and records that it
  /// was declared in [sourceFile].
  /// Returns an empty list if [configKey] is omitted or not a list.
  static List<LintTargetConfig> _parseConfigList(
    YamlMap toolConfig,
    String configKey,
    List<String> parsingErrors,
    String anchorDirectory,
    String? sourceFile,
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
        anchorDirectory,
        sourceFile,
      );
      if (config != null) {
        configs.add(config);
      }
    }
    return configs;
  }

  /// Parses a single dictionary element from a target list (`directories` or `individual_skills`).
  ///
  /// Validates the `path` string, anchors it to [anchorDirectory], and checks
  /// for unrecognized keys. Delegates parsing of sub-keys to
  /// [_parseLocalRulesForTarget] (`rules`) and [_parseIgnoreFileForTarget]
  /// (`ignore_file`). Returns `null` if `path` is invalid or missing.
  ///
  /// Diagnostics quote the path as authored so that error messages match the
  /// configuration file. The returned target also records where it was
  /// declared, read back with [declarationOf].
  static LintTargetConfig? _parseTargetEntry(
    YamlMap dir,
    String entryLabelCap,
    String entryLabelLower,
    List<String> parsingErrors,
    String anchorDirectory,
    String? sourceFile,
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

    final ({String? authored, String? resolved}) ignoreFile = _parseIgnoreFileForTarget(
      dir,
      path,
      entryLabelCap,
      parsingErrors,
      anchorDirectory,
    );

    final ({String file, int line})? source = sourceFile == null
        ? null
        : (file: sourceFile, line: _lineOf(dir, pathKey));
    return LintTargetConfig._parsed(
      path: canonicalizePath(path, baseDirectory: anchorDirectory),
      ruleConfigs: ruleConfigs,
      ignoreFile: ignoreFile.resolved,
      authoredPath: path,
      authoredIgnoreFile: ignoreFile.authored,
      declaration: TargetDeclaration(
        declaredPath: path,
        anchorDirectory: anchorDirectory,
        source: source,
      ),
    );
  }

  /// The 1-based line on which the value of [key] starts in [map].
  ///
  /// `package:yaml` records a position for every node, in block and flow
  /// style alike. Falls back to the start of [map] if [key] is absent.
  static int _lineOf(YamlMap map, String key) => (map.nodes[key]?.span ?? map.span).start.line + 1;

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
  /// Both are `null` when the key is absent or holds a non-string, in which
  /// case the default ignore file applies. If present but not a string, a type
  /// error is appended to [parsingErrors].
  static ({String? authored, String? resolved}) _parseIgnoreFileForTarget(
    YamlMap dir,
    String path,
    String entryLabelCap,
    List<String> parsingErrors,
    String anchorDirectory,
  ) {
    const ({String? authored, String? resolved}) absent = (authored: null, resolved: null);
    if (!dir.containsKey(ignoreFileKey)) {
      return absent;
    }
    final Object? ignoreFileValue = dir[ignoreFileKey];
    if (ignoreFileValue is String) {
      return (
        authored: ignoreFileValue,
        resolved: canonicalizePath(ignoreFileValue, baseDirectory: anchorDirectory),
      );
    }
    if (ignoreFileValue != null) {
      parsingErrors.add(
        '$entryLabelCap "$ignoreFileKey" for "$path" must be a string; '
        'got "$ignoreFileValue" (${ignoreFileValue.runtimeType}). '
        'Falling back to the default ignore file.',
      );
    }
    return absent;
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
  }) : _authoredPath = null,
       _authoredIgnoreFile = null,
       _declaration = null;

  /// Builds a target that remembers the path text it was declared with.
  ///
  /// Named parameters cannot start with an underscore, so [ConfigParser] reaches
  /// the private fields through this constructor.
  const LintTargetConfig._parsed({
    required this.path,
    required this.ruleConfigs,
    required this.ignoreFile,
    required String? authoredPath,
    required String? authoredIgnoreFile,
    required TargetDeclaration declaration,
  }) : _authoredPath = authoredPath,
       _authoredIgnoreFile = authoredIgnoreFile,
       _declaration = declaration;

  /// The path to the directory containing skills, or to an individual skill.
  ///
  /// Instances produced by [ConfigParser] hold an absolute, normalized path
  /// anchored to the directory of the configuration file that declared it.
  /// Instances constructed directly, such as configurations that are written
  /// back out as YAML, may hold a relative path and support tilde expansion
  /// (for example, `~/...`).
  final String path;
  final Map<String, RuleConfigPatch> ruleConfigs;

  /// The ignore file that applies to [path].
  ///
  /// Absolute on a target [ConfigParser] produced, and whatever the caller
  /// supplied on a target built directly.
  final String? ignoreFile;

  /// [path] as spelled in the configuration file, or `null` for a target built
  /// by a caller rather than read from a file.
  ///
  /// [path] alone cannot produce this text. `skills` anchored to `/repo/pkg`
  /// and `pkg/skills` anchored to `/repo` both resolve to `/repo/pkg/skills`,
  /// so [toYaml] emits this text instead and rewriting a configuration file
  /// leaves its paths as the author typed them.
  final String? _authoredPath;

  /// [ignoreFile] as spelled in the configuration file, or `null` for a target
  /// built by a caller rather than read from a file.
  final String? _authoredIgnoreFile;

  /// Where this target was declared, or `null` for a target built by a caller
  /// rather than read from a configuration. Read with [declarationOf].
  final TargetDeclaration? _declaration;

  /// Converts this target configuration into its YAML representation.
  Map<String, Object?> toYaml() {
    final map = <String, Object?>{ConfigParser.pathKey: _authoredPath ?? path};
    if (ruleConfigs.isNotEmpty) {
      map[ConfigParser.rulesKey] = <String, Object?>{
        for (final MapEntry<String, RuleConfigPatch> entry in ruleConfigs.entries)
          entry.key: entry.value.toYaml(),
      };
    }
    final String? targetIgnoreFile = _authoredIgnoreFile ?? ignoreFile;
    if (targetIgnoreFile != null) {
      map[ConfigParser.ignoreFileKey] = targetIgnoreFile;
    }
    return map;
  }

  /// Converts this target configuration into a formatted YAML string.
  String toYamlString() => ConfigSerializer.toYamlString(toYaml());

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

/// Returns where [target] was declared, or `null` for a target built by a
/// caller rather than read by [ConfigParser].
///
/// Internal to skills_lint: `package:skills_lint/skills_lint.dart` hides this
/// function, so the shape of [TargetDeclaration] can change freely.
TargetDeclaration? declarationOf(LintTargetConfig target) => target._declaration;

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

  /// Converts this configuration into its YAML representation.
  Map<String, Object?> toYaml() {
    final skillsLintMap = <String, Object?>{};

    if (ruleConfigs.isNotEmpty) {
      skillsLintMap[ConfigParser.rulesKey] = <String, Object?>{
        for (final MapEntry<String, RuleConfigPatch> entry in ruleConfigs.entries)
          entry.key: entry.value.toYaml(),
      };
    }

    if (directoryConfigs.isNotEmpty) {
      skillsLintMap[ConfigParser.directoriesKey] = <Map<String, Object?>>[
        for (final LintTargetConfig dir in directoryConfigs) dir.toYaml(),
      ];
    }

    if (individualSkillConfigs.isNotEmpty) {
      skillsLintMap[ConfigParser.individualSkillsKey] = <Map<String, Object?>>[
        for (final LintTargetConfig skill in individualSkillConfigs) skill.toYaml(),
      ];
    }

    return <String, Object?>{ConfigParser.skillsLintKey: skillsLintMap};
  }

  /// Converts this configuration into a formatted YAML string.
  String toYamlString() => ConfigSerializer.toYamlString(toYaml());

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
