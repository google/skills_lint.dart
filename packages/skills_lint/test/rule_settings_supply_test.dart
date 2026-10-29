// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_lint/skills_lint.dart';
import 'package:skills_lint/src/entry_point.dart' show createArgParser;
import 'package:skills_lint/src/models/check_type.dart';
import 'package:skills_lint/src/models/rule_parameter_type.dart';
import 'package:skills_lint/src/rule_registry.dart';
import 'package:skills_lint/src/rules/trailing_whitespace_rule.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// The ways a rule's settings can be supplied, from lowest to highest
/// precedence.
enum Layer {
  topLevel,
  directory,
  individualSkill,
  cli,
  api;

  bool get isYaml => const {topLevel, directory, individualSkill}.contains(this);
}

/// One rule's settings as supplied through one [Layer].
///
/// For [Layer.cli], a non-null `severity` passes `--<rule>` when it is
/// [AnalysisSeverity.error] and `--no-<rule>` otherwise.
typedef Setting = ({AnalysisSeverity? severity, Map<String, Object?> parameters});

/// Two distinct values for each parameter type: the first for a lower
/// [Layer], the second for a higher one.
const Map<RuleParameterType, List<Object>> _values = {
  RuleParameterType.string: ['lower-value', 'higher-value'],
  RuleParameterType.integer: [100, 200],
  RuleParameterType.boolean: [true, false],
  RuleParameterType.regExp: [r'^lower', r'^higher'],
  RuleParameterType.stringList: [
    ['lower'],
    ['higher'],
  ],
};

late Directory _tempDir;

/// The `directories` target that holds the skill.
String get _directoryPath => p.join(_tempDir.path, 'skills');

/// The skill, which is also the `individual_skills` target.
String get _skillPath => p.join(_directoryPath, 'my-skill');

/// Every pair of layers where the second takes precedence over the first.
/// The CLI and the Dart API supply the same argument, so they don't pair.
final List<(Layer, Layer)> _precedencePairs = [
  for (final Layer lower in Layer.values)
    for (final Layer higher in Layer.values)
      if (lower.index < higher.index && (lower.isYaml || higher.isYaml)) (lower, higher),
];

void main() {
  setUp(() => _tempDir = Directory.systemTemp.createTempSync('rule_settings_supply_'));
  tearDown(() => _tempDir.deleteSync(recursive: true));

  for (final CheckType check in RuleRegistry.allChecks) {
    group('${check.name} settings', () {
      _defineSeverityTests(check);
      for (final MapEntry<String, RuleParameterType> param in check.parameterSchema.entries) {
        _defineParameterTests(check, param.key, _values[param.value]!);
      }
    });
  }

  _defineValidateSkillsTests();
}

void _defineSeverityTests(CheckType check) {
  for (final Layer layer in Layer.values) {
    test('severity from ${layer.name} applies', () {
      final AnalysisSeverity severity = _severityFor(layer, other: check.defaultSeverity);

      final RuleConfig resolved = _resolve(check, {
        layer: (severity: severity, parameters: const {}),
      });

      expect(resolved.severity, severity);
    });
  }

  for (final (Layer lower, Layer higher) in _precedencePairs) {
    test('severity from ${higher.name} overrides ${lower.name}', () {
      final AnalysisSeverity lowerSeverity = _severityFor(
        lower,
        other: _severityFor(higher, other: check.defaultSeverity),
      );
      final AnalysisSeverity higherSeverity = _severityFor(higher, other: lowerSeverity);

      final RuleConfig resolved = _resolve(check, {
        lower: (severity: lowerSeverity, parameters: const {}),
        higher: (severity: higherSeverity, parameters: const {}),
      });

      expect(resolved.severity, higherSeverity);
    });
  }
}

/// Defines tests for the parameter [name] of [check], using the two distinct
/// [values] described in [_values].
void _defineParameterTests(CheckType check, String name, List<Object> values) {
  for (final Layer layer in Layer.values) {
    test('$name from ${layer.name} applies', () {
      final RuleConfig resolved = _resolve(check, {
        layer: (severity: null, parameters: {name: values[1]}),
      });

      expect(resolved.parameters[name], values[1]);
    });
  }

  for (final (Layer lower, Layer higher) in _precedencePairs) {
    test('$name from ${higher.name} overrides ${lower.name}', () {
      final RuleConfig resolved = _resolve(check, {
        lower: (severity: null, parameters: {name: values[0]}),
        higher: (severity: null, parameters: {name: values[1]}),
      });

      expect(resolved.parameters[name], values[1]);
    });

    test('$name from ${lower.name} survives a severity from ${higher.name}', () {
      final RuleConfig resolved = _resolve(check, {
        lower: (severity: null, parameters: {name: values[0]}),
        higher: (
          severity: _severityFor(higher, other: check.defaultSeverity),
          parameters: const {},
        ),
      });

      expect(resolved.parameters[name], values[0]);
    });
  }
}

/// A severity that [layer] can supply and that differs from [other].
AnalysisSeverity _severityFor(Layer layer, {required AnalysisSeverity other}) {
  if (layer == Layer.cli) {
    return other == AnalysisSeverity.error ? AnalysisSeverity.disabled : AnalysisSeverity.error;
  }
  return other == AnalysisSeverity.warning ? AnalysisSeverity.error : AnalysisSeverity.warning;
}

/// Supplies [settings] for [check] through each of their layers and returns
/// the configuration that applies to the skill.
RuleConfig _resolve(CheckType check, Map<Layer, Setting> settings) {
  final Configuration config = _parseYaml(check, settings);
  expect(config.parsingErrors, isEmpty);

  final Map<String, RuleConfigPatch> cliPatches = resolveRuleConfigsFromCli(
    createArgParser('help').parse(_cliArgs(check, settings[Layer.cli])),
  );
  final Map<String, RuleConfigPatch> apiPatches = {
    if (settings[Layer.api] case final Setting setting)
      check.name: RuleConfigPatch(
        severity: setting.severity,
        parameters: setting.parameters.isEmpty ? null : CustomRuleParameters(setting.parameters),
      ),
  };
  expect(
    cliPatches.isEmpty || apiPatches.isEmpty,
    isTrue,
    reason: 'The CLI and the Dart API each supply the same override argument.',
  );

  final session = ValidationSession(
    config: config,
    resolvedRuleConfigs: {...cliPatches, ...apiPatches},
    ignoreFileOverride: null,
    customRules: const [],
    printWarnings: false,
    fastFail: false,
    quiet: true,
    generateBaseline: false,
    fix: false,
    fixApply: false,
  );
  return session.resolveRuleConfigsForPath(_skillPath)[check.name]!;
}

/// Parses a `skills_lint.yaml` that supplies the YAML layers of [settings].
Configuration _parseYaml(CheckType check, Map<Layer, Setting> settings) {
  Map<String, Object?> rules(Layer layer) => {
    if (settings[layer] case final Setting setting)
      check.name: {
        if (setting.severity case final AnalysisSeverity severity) 'severity': severity.name,
        ...setting.parameters,
      },
  };

  final Map<String, Object?> yaml = {
    'skills_lint': {
      'rules': rules(Layer.topLevel),
      'directories': [
        {'path': _directoryPath, 'rules': rules(Layer.directory)},
      ],
      'individual_skills': [
        {'path': _skillPath, 'rules': rules(Layer.individualSkill)},
      ],
    },
  };
  // JSON is valid YAML.
  return ConfigParser.parse(jsonEncode(yaml), configSource: ConfigSource.directory(_tempDir.path));
}

/// The CLI arguments that supply [setting] for [check].
List<String> _cliArgs(CheckType check, Setting? setting) {
  if (setting == null) {
    return const [];
  }
  return [
    if (setting.severity == AnalysisSeverity.error)
      '--${check.name}'
    else if (setting.severity != null)
      '--no-${check.name}',
    for (final MapEntry<String, Object?> entry in setting.parameters.entries)
      for (final Object? value in [
        if (entry.value case final List<Object?> list) ...list else entry.value,
      ])
        '--${check.parameterFlag(entry.key)}=$value',
  ];
}

void _defineValidateSkillsTests() {
  group('validateSkills applies the setting that takes precedence', () {
    const String rule = TrailingWhitespaceRule.ruleName;

    setUp(() {
      Directory(_skillPath).createSync(recursive: true);
      File(p.join(_skillPath, 'SKILL.md')).writeAsStringSync(
        '${buildFrontmatter(name: 'my-skill', description: 'A test skill.')}Trailing space. \n',
      );
    });

    /// Validates the skill in `skills/my-skill`, which has trailing
    /// whitespace, with [rule] set to [topLevel] in `rules`, to [directory] in
    /// a `directories` entry for `skills`, to [individualSkill] in an
    /// `individual_skills` entry for the skill, and to [api] in
    /// `resolvedRuleConfigs`.
    Future<bool> validate({
      AnalysisSeverity? topLevel,
      AnalysisSeverity? directory,
      AnalysisSeverity? individualSkill,
      AnalysisSeverity? api,
    }) {
      return validateSkills(
        individualSkillPaths: [_skillPath],
        config: Configuration(
          ruleConfigs: {if (topLevel != null) rule: RuleConfigPatch(severity: topLevel)},
          directoryConfigs: [
            LintTargetConfig(
              path: _directoryPath,
              ruleConfigs: {if (directory != null) rule: RuleConfigPatch(severity: directory)},
            ),
          ],
          individualSkillConfigs: [
            LintTargetConfig(
              path: _skillPath,
              ruleConfigs: {
                if (individualSkill != null) rule: RuleConfigPatch(severity: individualSkill),
              },
            ),
          ],
        ),
        resolvedRuleConfigs: {if (api != null) rule: RuleConfigPatch(severity: api)},
        quiet: true,
      );
    }

    test('a directories entry over top-level rules', () async {
      expect(await validate(topLevel: AnalysisSeverity.error), isFalse);
      expect(
        await validate(topLevel: AnalysisSeverity.error, directory: AnalysisSeverity.disabled),
        isTrue,
      );
      expect(
        await validate(topLevel: AnalysisSeverity.disabled, directory: AnalysisSeverity.error),
        isFalse,
      );
    });

    test('an individual_skills entry over a directories entry', () async {
      expect(
        await validate(
          directory: AnalysisSeverity.error,
          individualSkill: AnalysisSeverity.disabled,
        ),
        isTrue,
      );
      expect(
        await validate(
          directory: AnalysisSeverity.disabled,
          individualSkill: AnalysisSeverity.error,
        ),
        isFalse,
      );
    });

    test('resolvedRuleConfigs over the configuration', () async {
      expect(
        await validate(individualSkill: AnalysisSeverity.error, api: AnalysisSeverity.disabled),
        isTrue,
      );
      expect(
        await validate(individualSkill: AnalysisSeverity.disabled, api: AnalysisSeverity.error),
        isFalse,
      );
    });
  });
}
