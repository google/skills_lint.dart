// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:args/args.dart';
import 'package:skills_lint/src/config_parser.dart';
import 'package:skills_lint/src/entry_point.dart';
import 'package:skills_lint/src/models/analysis_severity.dart';
import 'package:skills_lint/src/models/check_type.dart';
import 'package:skills_lint/src/models/custom_rule_parameters.dart';
import 'package:skills_lint/src/models/parameter_constraint.dart';
import 'package:skills_lint/src/models/rule_parameter_type.dart';
import 'package:skills_lint/src/rule_registry.dart';
import 'package:skills_lint/src/rules/description_length_rule.dart';
import 'package:test/test.dart';

// A constraint that no built-in rule uses, so these tests exercise the
// mechanism rather than one rule's policy.
const _evenInteger = ParameterConstraint(description: 'an even integer', accepts: _isEven);

bool _isEven(Object value) => value is int && value.isEven;

const _mockCheck = CheckType(
  name: 'mock-rule',
  defaultSeverity: AnalysisSeverity.disabled,
  help: 'Mock rule.',
  parameterSchema: {'count': RuleParameterType.integer, 'label': RuleParameterType.string},
  parameterConstraints: {'count': _evenInteger},
);

/// A value that each constrained built-in parameter must reject, keyed by
/// rule name and then parameter name.
///
/// A test below fails when a built-in rule declares a constraint that has no
/// entry here, so every new constraint gets the end-to-end checks.
const Map<String, Map<String, Object>> _rejectedValues = {
  DescriptionLengthRule.ruleName: {DescriptionLengthRule.maxDescriptionLengthParameter: 0},
};

List<(CheckType, String)> _builtInConstrainedParameters() => [
  for (final CheckType check in RuleRegistry.allChecks)
    for (final String param in check.parameterConstraints.keys) (check, param),
];

CustomRuleParameters _params(Map<String, Object?> values) => CustomRuleParameters(values);

void main() {
  group('ParameterConstraint', () {
    test('accepts exactly the values its predicate accepts', () {
      expect(_evenInteger.accepts(2), isTrue);
      expect(_evenInteger.accepts(3), isFalse);
      expect(_evenInteger.accepts('2'), isFalse);
    });
  });

  group('CheckType.validateParameters with a constraint', () {
    test('accepts a value that meets the constraint', () {
      expect(_mockCheck.validateParameters(_params({'count': 4})), isEmpty);
    });

    test('rejects a value that breaks the constraint, naming the accepted values', () {
      final List<String> errors = _mockCheck.validateParameters(_params({'count': 3}));

      expect(errors, [
        allOf(contains('"count"'), contains('"mock-rule"'), contains('an even integer')),
      ]);
    });

    test('reports a wrong type once, without also applying the constraint', () {
      final List<String> errors = _mockCheck.validateParameters(_params({'count': 'x'}));

      expect(errors, [allOf(contains('Expected int'), isNot(contains('an even integer')))]);
    });

    test('skips null values, which clear a parameter', () {
      expect(_mockCheck.validateParameters(_params({'count': null})), isEmpty);
    });
  });

  group('CheckType.validateConstrainedParameters', () {
    test('reports type and constraint errors for constrained parameters', () {
      expect(_mockCheck.validateConstrainedParameters(_params({'count': 3})), hasLength(1));
      expect(_mockCheck.validateConstrainedParameters(_params({'count': 'x'})), hasLength(1));
    });

    test('ignores unconstrained and unrecognized parameters', () {
      final CustomRuleParameters params = _params({'label': 5, 'unknown': true, 'count': 4});

      expect(_mockCheck.validateConstrainedParameters(params), isEmpty);
    });
  });

  group('built-in rules enforce their parameter constraints', () {
    test('every constraint applies to a parameter in the rule schema', () {
      for (final (CheckType check, String param) in _builtInConstrainedParameters()) {
        expect(check.parameterSchema, contains(param), reason: '${check.name} $param');
      }
    });

    test('every constrained parameter has a rejected value in this test', () {
      for (final (CheckType check, String param) in _builtInConstrainedParameters()) {
        expect(_rejectedValues[check.name], contains(param), reason: '${check.name} $param');
      }
    });

    for (final MapEntry(key: String ruleName, value: Map<String, Object> params)
        in _rejectedValues.entries) {
      for (final MapEntry(key: String param, value: Object rejected) in params.entries) {
        final label = '$ruleName $param: $rejected';

        test('$label is a skills_lint.yaml configuration error', () {
          final Configuration config = ConfigParser.parse('''
skills_lint:
  rules:
    $ruleName:
      $param: $rejected
''');

          expect(config.parsingErrors, [contains('"$param"')]);
        });

        test('$label is a CLI usage error', () {
          final flag = '$ruleName-$param';
          final ArgResults results = (ArgParser()..addOption(flag)).parse(['--$flag=$rejected']);

          expect(() => resolveRuleConfigsFromCli(results), throwsFormatException);
        });

        test('$label is rejected through the Dart API', () {
          expect(
            () => RuleRegistry.createRule(
              ruleName,
              AnalysisSeverity.error,
              _params({param: rejected}),
            ),
            throwsArgumentError,
          );
        });
      }
    }
  });
}
