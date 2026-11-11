// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../src/models/convention_violation.dart';
import '../src/models/source.dart';
import '../src/yaml_loading.dart';

/// Runs [findRawYamlLoads] over small inline snippets, which pins which
/// references to `package:yaml`'s loaders it reports independently of the
/// package's code.
///
/// The repo-wide scan in `yaml_load_convention_test.dart` relies on this: a
/// parse that skips `YamlLimits` reads unbounded input, so the detector must
/// catch each way of naming a loader and leave `YamlLimits` itself alone.
void main() {
  group('findRawYamlLoads', () {
    test('reports calls and tear-offs of every package:yaml loader', () {
      final source = Source.snippet('''
import 'package:yaml/yaml.dart';

void run(String text, List<String> texts) {
  loadYaml(text);
  loadYamlNode(text);
  loadYamlDocument(text);
  loadYamlDocuments(text);
  loadYamlStream(text);
  texts.map(loadYaml);
  final Object? Function(String) parse = loadYamlNode;
  loadYaml.call(text);
}
''');
      final List<ConventionViolation> violations = findRawYamlLoads(source);
      expect(_lines(violations), [4, 5, 6, 7, 8, 9, 10, 11]);
      expect(
        violations.first.problem,
        'calls loadYaml from package:yaml instead of YamlLimits.loadYaml',
      );
      expect(
        violations[5].problem,
        'tears off loadYaml from package:yaml instead of YamlLimits.loadYaml',
      );
    });

    test('reports loaders behind an import prefix', () {
      final source = Source.snippet('''
import 'package:yaml/yaml.dart' as yaml;

void run(String text, List<String> texts) {
  yaml.loadYaml(text);
  texts.map(yaml.loadYamlNode);
}
''');
      final List<ConventionViolation> violations = findRawYamlLoads(source);
      expect(_lines(violations), [4, 5]);
      expect(violations.first.problem, startsWith('calls yaml.loadYaml '));
      expect(violations.last.problem, startsWith('tears off yaml.loadYamlNode '));
    });

    test('honors show and hide combinators', () {
      final source = Source.snippet('''
import 'package:yaml/yaml.dart' show loadYamlNode, YamlMap;
import 'package:yaml/yaml.dart' as y hide loadYaml;

void run(String text) {
  loadYamlNode(text);
  y.loadYamlNode(text);
  loadYaml(text);
  y.loadYaml(text);
}
''');
      expect(_lines(findRawYamlLoads(source)), [5, 6]);
    });

    test('ignores YamlLimits, other prefixes, members, comments and labels', () {
      final source = Source.snippet('''
import 'package:yaml/yaml.dart';
import 'package:other/other.dart' as other;

/// Parses like [loadYaml] and [YamlLimits.loadYaml].
void run(String text, Parser parser, List<String> texts) {
  YamlLimits.loadYaml(text);
  texts.map(YamlLimits.loadYaml);
  other.loadYaml(text);
  parser.loadYaml(text);
  parser.inner.loadYaml(text);
  parser.inner.loadYaml;
  configure(loadYaml: true);
  // loadYaml(text);
  YamlMap? map;
}
''');
      expect(findRawYamlLoads(source), isEmpty);
    });

    test('ignores files that do not import package:yaml', () {
      final source = Source.snippet('''
import 'yaml_limits.dart';

Object? loadYaml(String text) => YamlLimits.loadYaml(text);

void run(String text) {
  loadYaml(text);
}
''');
      expect(findRawYamlLoads(source), isEmpty);
    });
  });
}

List<int> _lines(Iterable<ConventionViolation> violations) => [for (final v in violations) v.line];
