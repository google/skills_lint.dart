// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_lint/src/config_parser.dart';
import 'package:skills_lint/src/config_source.dart';
import 'package:skills_lint/src/entry_point.dart';
import 'package:skills_lint/src/models/analysis_severity.dart';
import 'package:skills_lint/src/models/check_type.dart';
import 'package:skills_lint/src/models/custom_rule_parameters.dart';
import 'package:skills_lint/src/models/rule_config.dart';
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

  bool get isYaml => index <= individualSkill.index;
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

void main() {
  late Directory tempDir;
  late String directoryPath;
  late String skillPath;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('rule_settings_supply_');
    directoryPath = p.join(tempDir.path, 'skills');
    skillPath = p.join(directoryPath, 'my-skill');
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  /// Supplies [settings] for [check] through each of their layers and returns
  /// the configuration that applies to the skill.
  RuleConfig resolve(CheckType check, Map<Layer, Setting> settings) {
    Map<String, Object?> yamlRule(Setting setting) => {
      if (setting.severity != null) 'severity': setting.severity!.name,
      ...setting.parameters,
    };
    Map<String, Object?> yamlRules(Layer layer) => {
      if (settings[layer] case final Setting setting) check.name: yamlRule(setting),
    };

    final yaml = <String, Object?>{
      'rules': yamlRules(Layer.topLevel),
      'directories': [
        {'path': directoryPath, 'rules': yamlRules(Layer.directory)},
      ],
      'individual_skills': [
        {'path': skillPath, 'rules': yamlRules(Layer.individualSkill)},
      ],
    };
    // JSON is valid YAML.
    final Configuration config = ConfigParser.parse(
      jsonEncode({'skills_lint': yaml}),
      configSource: ConfigSource.directory(tempDir.path),
    );
    expect(config.parsingErrors, isEmpty);

    final args = <String>[];
    if (settings[Layer.cli] case final Setting setting) {
      if (setting.severity case final AnalysisSeverity severity) {
        args.add(severity == AnalysisSeverity.error ? '--${check.name}' : '--no-${check.name}');
      }
      for (final MapEntry<String, Object?> entry in setting.parameters.entries) {
        final flag = '--${check.parameterFlag(entry.key)}';
        final Object? value = entry.value;
        if (value is List) {
          args.addAll([for (final Object? item in value) '$flag=$item']);
        } else {
          args.add('$flag=$value');
        }
      }
    }
    final Map<String, RuleConfigPatch> cliPatches = resolveRuleConfigsFromCli(
      createArgParser('help').parse(args),
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
    return session.resolveRuleConfigsForPath(skillPath)[check.name]!;
  }

  /// A severity that [layer] can supply and that differs from [other].
  AnalysisSeverity severityFor(Layer layer, {required AnalysisSeverity other}) {
    if (layer == Layer.cli) {
      return other == AnalysisSeverity.error ? AnalysisSeverity.disabled : AnalysisSeverity.error;
    }
    return other == AnalysisSeverity.warning ? AnalysisSeverity.error : AnalysisSeverity.warning;
  }

  /// Every pair of layers where the second takes precedence over the first.
  /// The CLI and the Dart API supply the same argument, so they don't pair.
  final List<(Layer, Layer)> precedencePairs = [
    for (final Layer lower in Layer.values)
      for (final Layer higher in Layer.values)
        if (lower.index < higher.index && (lower.isYaml || higher.isYaml)) (lower, higher),
  ];

  for (final CheckType check in RuleRegistry.allChecks) {
    group('${check.name} settings', () {
      for (final Layer layer in Layer.values) {
        test('severity from ${layer.name} applies', () {
          final AnalysisSeverity severity = severityFor(layer, other: check.defaultSeverity);

          final RuleConfig resolved = resolve(check, {
            layer: (severity: severity, parameters: const {}),
          });

          expect(resolved.severity, severity);
        });
      }

      for (final (Layer lower, Layer higher) in precedencePairs) {
        test('severity from ${higher.name} overrides ${lower.name}', () {
          final AnalysisSeverity lowerSeverity = severityFor(
            lower,
            other: severityFor(higher, other: check.defaultSeverity),
          );
          final AnalysisSeverity higherSeverity = severityFor(higher, other: lowerSeverity);

          final RuleConfig resolved = resolve(check, {
            lower: (severity: lowerSeverity, parameters: const {}),
            higher: (severity: higherSeverity, parameters: const {}),
          });

          expect(resolved.severity, higherSeverity);
        });
      }

      for (final MapEntry<String, RuleParameterType> param in check.parameterSchema.entries) {
        final List<Object> values = _values[param.value]!;

        for (final Layer layer in Layer.values) {
          test('${param.key} from ${layer.name} applies', () {
            final RuleConfig resolved = resolve(check, {
              layer: (severity: null, parameters: {param.key: values[1]}),
            });

            expect(resolved.parameters[param.key], values[1]);
          });
        }

        for (final (Layer lower, Layer higher) in precedencePairs) {
          test('${param.key} from ${higher.name} overrides ${lower.name}', () {
            final RuleConfig resolved = resolve(check, {
              lower: (severity: null, parameters: {param.key: values[0]}),
              higher: (severity: null, parameters: {param.key: values[1]}),
            });

            expect(resolved.parameters[param.key], values[1]);
          });

          test('${param.key} from ${lower.name} survives a severity from ${higher.name}', () {
            final RuleConfig resolved = resolve(check, {
              lower: (severity: null, parameters: {param.key: values[0]}),
              higher: (
                severity: severityFor(higher, other: check.defaultSeverity),
                parameters: const {},
              ),
            });

            expect(resolved.parameters[param.key], values[0]);
          });
        }
      }
    });
  }

  group('validateSkills applies the setting that takes precedence', () {
    const String rule = TrailingWhitespaceRule.ruleName;

    /// Validates a skill with trailing whitespace in `skills/my-skill`, with
    /// [rule] set to [topLevel] in `rules`, to [directory] in a `directories`
    /// entry for `skills`, and to [api] in `resolvedRuleConfigs`.
    Future<bool> validate({
      AnalysisSeverity? topLevel,
      AnalysisSeverity? directory,
      AnalysisSeverity? api,
    }) async {
      await File(p.join(skillPath, 'SKILL.md')).create(recursive: true);
      await File(p.join(skillPath, 'SKILL.md')).writeAsString(
        '${buildFrontmatter(name: 'my-skill', description: 'A test skill.')}Trailing space. \n',
      );
      return validateSkills(
        individualSkillPaths: [skillPath],
        config: Configuration(
          ruleConfigs: {if (topLevel != null) rule: RuleConfigPatch(severity: topLevel)},
          directoryConfigs: [
            LintTargetConfig(
              path: directoryPath,
              ruleConfigs: {if (directory != null) rule: RuleConfigPatch(severity: directory)},
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

    test('resolvedRuleConfigs over the configuration', () async {
      expect(
        await validate(directory: AnalysisSeverity.error, api: AnalysisSeverity.disabled),
        isTrue,
      );
      expect(
        await validate(directory: AnalysisSeverity.disabled, api: AnalysisSeverity.error),
        isFalse,
      );
    });
  });
}
