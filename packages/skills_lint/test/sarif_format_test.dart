// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_lint/skills_lint.dart';
import 'package:test/test.dart';
import 'test_utils.dart';

void main() {
  group('SARIF 2.1.0 Data Models and Serialization', () {
    test('severityToSarifLevel maps severities correctly', () {
      expect(SarifSerializer.severityToSarifLevel(AnalysisSeverity.error), equals('error'));
      expect(SarifSerializer.severityToSarifLevel(AnalysisSeverity.warning), equals('warning'));
      expect(SarifSerializer.severityToSarifLevel(AnalysisSeverity.disabled), equals('none'));
    });

    test('SarifLog round-trips to and from JSON', () {
      const log = SarifLog(
        runs: [
          SarifRun(
            tool: SarifTool(
              driver: SarifDriver(
                rules: [
                  SarifRule(
                    id: 'valid-yaml-metadata',
                    shortDescription: SarifMessage(text: 'Check if YAML metadata is valid.'),
                    helpUri: 'https://github.com/google/skills_lint.dart',
                    defaultConfiguration: SarifReportingConfiguration(level: 'error'),
                  ),
                ],
              ),
            ),
            results: [
              SarifResult(
                ruleId: 'valid-yaml-metadata',
                level: 'error',
                message: SarifMessage(text: 'Missing YAML frontmatter'),
                ruleIndex: 0,
                locations: [
                  SarifLocation(
                    physicalLocation: SarifPhysicalLocation(
                      artifactLocation: SarifArtifactLocation(uri: 'skills/my-skill/SKILL.md'),
                      region: SarifRegion(startLine: 1, startColumn: 1, endLine: 2, endColumn: 5),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      );

      final Map<String, dynamic> jsonMap = log.toJson();
      expect(
        jsonMap[r'$schema'],
        equals(
          'https://docs.oasis-open.org/sarif/sarif/v2.1.0/errata01/os/schemas/sarif-schema-2.1.0.json',
        ),
      );
      expect(jsonMap['version'], equals('2.1.0'));
      expect(jsonMap['runs'], isA<List<dynamic>>());

      final deserialized = SarifLog.fromJson(jsonMap);
      expect(deserialized.version, equals('2.1.0'));
      expect(deserialized.runs.length, equals(1));
      expect(deserialized.runs.first.tool.driver.name, equals('skills_lint'));
      expect(deserialized.runs.first.tool.driver.rules.first.id, equals('valid-yaml-metadata'));
      expect(deserialized.runs.first.results.length, equals(1));
      expect(deserialized.runs.first.results.first.ruleId, equals('valid-yaml-metadata'));
      expect(deserialized.runs.first.results.first.level, equals('error'));
      expect(
        deserialized.runs.first.results.first.locations.first.physicalLocation.artifactLocation.uri,
        equals('skills/my-skill/SKILL.md'),
      );
      expect(
        deserialized.runs.first.results.first.locations.first.physicalLocation.region?.startLine,
        equals(1),
      );
      expect(
        deserialized.runs.first.results.first.locations.first.physicalLocation.region?.startColumn,
        equals(1),
      );
      expect(
        deserialized.runs.first.results.first.locations.first.physicalLocation.region?.endLine,
        equals(2),
      );
      expect(
        deserialized.runs.first.results.first.locations.first.physicalLocation.region?.endColumn,
        equals(5),
      );
    });

    test('SarifSerializer builds empty results for clean run', () {
      final SarifLog sarif = SarifSerializer.toSarifLog([]);
      expect(sarif.runs.length, equals(1));
      expect(sarif.runs.first.results, isEmpty);
      expect(sarif.runs.first.tool.driver.rules, isNotEmpty);
      expect(sarif.runs.first.tool.driver.rules.any((r) => r.id == 'path-does-not-exist'), isTrue);
    });

    test('SarifSerializer uses explicit line and column coordinates from error object', () {
      final skillDir = Directory('/tmp/mock_skill');
      final context = SkillContext(directory: skillDir, rawContent: 'Line 1\nLine 2');

      final result = ValidationResult(
        context: context,
        validationErrors: [
          ValidationError(
            ruleId: 'check-trailing-whitespace',
            file: 'SKILL.md',
            message: 'Line 12 has 1 trailing space(s).',
            severity: AnalysisSeverity.warning,
            region: const SourceRegion(startLine: 12),
          ),
          ValidationError(
            ruleId: 'description-too-long',
            file: 'SKILL.md',
            message: 'Description exceeds 500 characters',
            severity: AnalysisSeverity.error,
            region: const SourceRegion(startLine: 5, startColumn: 10),
          ),
          ValidationError(
            ruleId: 'path-does-not-exist',
            file: 'SKILL.md',
            message: 'File not found',
            severity: AnalysisSeverity.error,
          ),
        ],
      );

      final SarifLog sarif = SarifSerializer.toSarifLog([result]);
      expect(sarif.runs.first.results.length, equals(3));

      final SarifResult first = sarif.runs.first.results[0];
      expect(first.ruleId, equals('check-trailing-whitespace'));
      expect(first.level, equals('warning'));
      expect(first.locations.first.physicalLocation.region?.startLine, equals(12));

      final SarifResult second = sarif.runs.first.results[1];
      expect(second.ruleId, equals('description-too-long'));
      expect(second.level, equals('error'));
      expect(second.locations.first.physicalLocation.region?.startLine, equals(5));
      expect(second.locations.first.physicalLocation.region?.startColumn, equals(10));

      final SarifResult third = sarif.runs.first.results[2];
      expect(third.ruleId, equals('path-does-not-exist'));
      expect(third.locations.first.physicalLocation.region?.startLine, equals(1));
    });

    test('SarifSerializer omits ignored and disabled errors from results', () {
      final result = ValidationResult(
        validationErrors: [
          ValidationError(
            ruleId: 'check-trailing-whitespace',
            file: 'SKILL.md',
            message: 'Line 2 has trailing spaces',
            severity: AnalysisSeverity.warning,
            isIgnored: true,
          ),
          ValidationError(
            ruleId: 'disabled-rule',
            file: 'SKILL.md',
            message: 'Disabled rule error',
            severity: AnalysisSeverity.disabled,
          ),
          ValidationError(
            ruleId: 'invalid-skill-name',
            file: 'SKILL.md',
            message: 'Invalid skill name',
            severity: AnalysisSeverity.error,
          ),
        ],
      );

      final SarifLog sarif = SarifSerializer.toSarifLog([result]);
      expect(sarif.runs.first.results.length, equals(1));
      expect(sarif.runs.first.results.first.ruleId, equals('invalid-skill-name'));
    });

    test(
      'SarifSerializer resolves URIs relative to rootDirectory with %SRCROOT% and handles external paths without uriBaseId',
      () {
        final String rootDir = p.normalize(p.absolute('/workspace/project'));
        final insideContext = SkillContext(
          directory: Directory(p.join(rootDir, 'skills', 'test-skill')),
          rawContent: 'test',
        );

        final insideResult = ValidationResult(
          context: insideContext,
          validationErrors: [
            ValidationError(
              ruleId: 'valid-yaml-metadata',
              file: 'SKILL.md',
              message: 'Error in skill',
              severity: AnalysisSeverity.error,
            ),
          ],
        );

        final externalResult = ValidationResult(
          validationErrors: [
            ValidationError(
              ruleId: 'path-does-not-exist',
              file: p.normalize(p.absolute('/tmp/external-location/SKILL.md')),
              message: 'External file error',
              severity: AnalysisSeverity.error,
            ),
          ],
        );

        final rootDirResult = ValidationResult(
          validationErrors: [
            ValidationError(
              ruleId: 'path-does-not-exist',
              file: rootDir,
              message: 'Root directory error',
              severity: AnalysisSeverity.error,
            ),
          ],
        );

        final SarifLog sarif = SarifSerializer.toSarifLog([
          insideResult,
          externalResult,
          rootDirResult,
        ], rootDirectory: rootDir);

        expect(sarif.runs.first.results.length, equals(3));

        // 1. Inside file -> relative URI + %SRCROOT% uriBaseId
        final SarifResult res1 = sarif.runs.first.results[0];
        final SarifArtifactLocation loc1 = res1.locations.first.physicalLocation.artifactLocation;
        expect(loc1.uri, equals('skills/test-skill/SKILL.md'));
        expect(loc1.uriBaseId, equals('%SRCROOT%'));

        // 2. External file -> absolute URI + null uriBaseId (OASIS SARIF §3.4.4)
        final SarifResult res2 = sarif.runs.first.results[1];
        final SarifArtifactLocation loc2 = res2.locations.first.physicalLocation.artifactLocation;
        expect(loc2.uri, startsWith('file://'));
        expect(loc2.uri, contains('external-location/SKILL.md'));
        expect(loc2.uriBaseId, isNull);

        // 3. Root directory itself -> relative URI + %SRCROOT% uriBaseId
        final SarifResult res3 = sarif.runs.first.results[2];
        final SarifArtifactLocation loc3 = res3.locations.first.physicalLocation.artifactLocation;
        expect(loc3.uri, anyOf('.', './'));
        expect(loc3.uriBaseId, equals('%SRCROOT%'));
      },
    );

    test('SarifSerializer includes custom rules in driver rules list with tags', () {
      final customRule = _MockCustomRule();
      final SarifLog sarif = SarifSerializer.toSarifLog([], customRules: [customRule]);

      final SarifDriver driver = sarif.runs.first.tool.driver;
      expect(driver.rules.any((r) => r.id == 'custom-test-rule'), isTrue);

      final SarifRule defaultRule = driver.rules.firstWhere((r) => r.id == 'path-does-not-exist');
      expect(defaultRule.properties, isNotNull);
      expect(defaultRule.properties![SarifRule.keyTags], equals(['lint', 'quality']));
      expect(defaultRule.properties![SarifRule.keyProblemSeverity], equals('recommendation'));
      expect(defaultRule.properties![SarifRule.keyPrecision], equals('very-high'));

      final SarifRule customSarifRule = driver.rules.firstWhere((r) => r.id == 'custom-test-rule');
      expect(customSarifRule.properties, isNotNull);
      expect(
        customSarifRule.properties![SarifRule.keyTags],
        equals(['lint', 'quality', 'custom-rule']),
      );
    });
  });

  group('ValidationSession Format Integration', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('sarif_session_test.');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('ValidationSession collects results and generates valid SARIF JSON', () async {
      final Directory skillDir = await Directory('${tempDir.path}/test-skill').create();
      await File('${skillDir.path}/SKILL.md').writeAsString('''
---
name: test-skill
description: A valid test skill
---
Body content
''');

      final session = ValidationSession(
        config: const Configuration(),
        ignoreFileOverride: null,
        customRules: const [],
        printWarnings: true,
        fastFail: false,
        quiet: true,
        generateBaseline: false,
        fix: false,
        fixApply: false,
        format: OutputFormat.sarif,
      );

      final bool proceed = await session.processIndividualSkill(skillDir.path);
      expect(proceed, isTrue);
      expect(session.anyFailed, isFalse);
      expect(session.results.length, equals(1));

      final String sarifJson = session.toSarifJson();
      final jsonMap = jsonDecode(sarifJson) as Map<String, dynamic>;
      expect(jsonMap['version'], equals('2.1.0'));
      expect(jsonMap['runs'], isA<List<dynamic>>());
      final runs = jsonMap['runs'] as List<dynamic>;
      expect(runs.length, equals(1));
      final run = runs.first as Map<String, dynamic>;
      expect(run['results'], isEmpty);
    });

    test('ValidationSession generates raw JSON array for --format=json', () async {
      final Directory skillDir = await Directory('${tempDir.path}/invalid-skill').create();
      await File('${skillDir.path}/SKILL.md').writeAsString('No frontmatter at all');

      final session = ValidationSession(
        config: const Configuration(),
        ignoreFileOverride: null,
        customRules: const [],
        printWarnings: true,
        fastFail: false,
        quiet: true,
        generateBaseline: false,
        fix: false,
        fixApply: false,
        format: OutputFormat.json,
      );

      await session.processIndividualSkill(skillDir.path);
      expect(session.anyFailed, isTrue);

      final String jsonOutput = session.toJsonOutput();
      final jsonList = jsonDecode(jsonOutput) as List<dynamic>;
      expect(jsonList.length, equals(1));

      final firstSkill = jsonList.first as Map<String, dynamic>;
      expect(firstSkill['skillName'], equals('invalid-skill'));
      expect(firstSkill['isValid'], isFalse);
      expect(firstSkill['errors'], isNotEmpty);
      expect(firstSkill['validationErrors'], isNotEmpty);
    });

    test('OutputFormat.fromString parses formats and throws on invalid values', () {
      expect(OutputFormat.fromString('text'), equals(OutputFormat.text));
      expect(OutputFormat.fromString('json'), equals(OutputFormat.json));
      expect(OutputFormat.fromString('sarif'), equals(OutputFormat.sarif));
      expect(OutputFormat.fromString('SARIF'), equals(OutputFormat.sarif));
      expect(() => OutputFormat.fromString('xml'), throwsA(isA<ArgumentError>()));
    });

    test('hasInvalidFixFormatCombination validates fix and format compatibility', () {
      expect(hasInvalidFixFormatCombination(fix: true, format: OutputFormat.text), isFalse);
      expect(hasInvalidFixFormatCombination(fix: false, format: OutputFormat.text), isFalse);
      expect(hasInvalidFixFormatCombination(fix: false, format: OutputFormat.sarif), isFalse);
      expect(hasInvalidFixFormatCombination(fix: false, format: OutputFormat.json), isFalse);
      expect(hasInvalidFixFormatCombination(fix: true, format: OutputFormat.sarif), isTrue);
      expect(hasInvalidFixFormatCombination(fix: true, format: OutputFormat.json), isTrue);
    });

    test(
      'ValidationSession emits SARIF URIs relative to execution root without ../ prefix',
      () async {
        final Directory skillDir = await Directory(
          '${tempDir.path}/skills/invalid-skill',
        ).create(recursive: true);
        await File(
          '${skillDir.path}/SKILL.md',
        ).writeAsString('Invalid YAML content without frontmatter');

        final session = ValidationSession(
          config: const Configuration(),
          ignoreFileOverride: null,
          customRules: const [],
          printWarnings: true,
          fastFail: false,
          quiet: true,
          generateBaseline: false,
          fix: false,
          fixApply: false,
          format: OutputFormat.sarif,
        );

        await session.processIndividualSkill(skillDir.path);
        expect(session.anyFailed, isTrue);

        final String sarifJson = session.toSarifJson();
        final jsonMap = jsonDecode(sarifJson) as Map<String, dynamic>;
        final runs = jsonMap['runs'] as List<dynamic>;
        final run = runs.first as Map<String, dynamic>;
        final results = run['results'] as List<dynamic>;
        expect(results, isNotEmpty);

        for (final result in results) {
          final resultMap = result as Map<String, dynamic>;
          final locations = resultMap['locations'] as List<dynamic>;
          for (final loc in locations) {
            final locMap = loc as Map<String, dynamic>;
            final phys = locMap['physicalLocation'] as Map<String, dynamic>;
            final artifactLoc = phys['artifactLocation'] as Map<String, dynamic>;
            final uri = artifactLoc['uri'] as String;
            expect(
              uri.startsWith('../'),
              isFalse,
              reason: 'SARIF URI "$uri" should not escape execution root',
            );
          }
        }
      },
    );
  });

  group('ValidationError and ValidationResult JSON methods', () {
    test('ValidationError toJson and fromJson round-trip', () {
      final error = ValidationError(
        ruleId: 'valid-yaml-metadata',
        file: 'SKILL.md',
        message: 'Invalid metadata',
        severity: AnalysisSeverity.error,
        region: const SourceRegion(startLine: 10, startColumn: 4, endLine: 12, endColumn: 8),
      );

      final Map<String, Object?> json = error.toJson();
      expect(json['ruleId'], equals('valid-yaml-metadata'));
      expect(json['file'], equals('SKILL.md'));
      expect(json['message'], equals('Invalid metadata'));
      expect(json['severity'], equals('error'));
      expect(json['isIgnored'], isFalse);
      expect(json['region'], isA<Map<String, Object?>>());
      final regionJson = json['region']! as Map<String, Object?>;
      expect(regionJson['startLine'], equals(10));
      expect(regionJson['startColumn'], equals(4));
      expect(regionJson['endLine'], equals(12));
      expect(regionJson['endColumn'], equals(8));

      final deserialized = ValidationError.fromJson(json);
      expect(deserialized.ruleId, equals(error.ruleId));
      expect(deserialized.file, equals(error.file));
      expect(deserialized.message, equals(error.message));
      expect(deserialized.severity, equals(error.severity));
      expect(deserialized.isIgnored, equals(error.isIgnored));
      expect(deserialized.region?.startLine, equals(error.region?.startLine));
      expect(deserialized.region?.startColumn, equals(error.region?.startColumn));
      expect(deserialized.region?.endLine, equals(error.region?.endLine));
      expect(deserialized.region?.endColumn, equals(error.region?.endColumn));
    });

    test('ValidationResult toJson and fromJson round-trip', () {
      final result = ValidationResult(
        validationErrors: [
          ValidationError(
            ruleId: 'check-trailing-whitespace',
            file: 'SKILL.md',
            message: 'Trailing whitespace',
            severity: AnalysisSeverity.warning,
          ),
        ],
        warnings: ['Manual warning note'],
      );

      final Map<String, dynamic> json = result.toJson();
      expect(json['isValid'], isTrue);
      expect(json['warnings'], contains('Manual warning note'));
      expect(json['validationErrors'], isA<List<dynamic>>());

      final deserialized = ValidationResult.fromJson(json);
      expect(deserialized.isValid, isTrue);
      expect(deserialized.warnings, contains('Manual warning note'));
      expect(deserialized.validationErrors.length, equals(1));
      expect(deserialized.validationErrors.first.ruleId, equals('check-trailing-whitespace'));
    });
    _testIndividualSarifModels();
  });
}

void _testIndividualSarifModels() {
  group('Individual SARIF Model Round-Trip Serialization', () {
    test('SarifArtifactLocation positive round-trip', () {
      const full = SarifArtifactLocation(uri: 'skills/my-skill/SKILL.md', uriBaseId: '%SRCROOT%');
      expectJsonRoundTrip<SarifArtifactLocation>(
        instance: full,
        toJson: (a) => a.toJson(),
        fromJson: SarifArtifactLocation.fromJson,
      );

      const minimal = SarifArtifactLocation(uri: 'SKILL.md');
      expectJsonRoundTrip<SarifArtifactLocation>(
        instance: minimal,
        toJson: (a) => a.toJson(),
        fromJson: SarifArtifactLocation.fromJson,
      );
    });

    test('SarifArtifactLocation negative handling on malformed JSON', () {
      expect(() => SarifArtifactLocation.fromJson(const {'uri': 123}), throwsA(isA<TypeError>()));
    });

    test('SarifDriver positive round-trip', () {
      const full = SarifDriver(
        name: 'custom_linter',
        version: '1.2.3',
        informationUri: 'https://example.com/tool',
        rules: [
          SarifRule(
            id: 'rule-1',
            shortDescription: SarifMessage(text: 'Rule 1 description'),
            fullDescription: SarifMessage(text: 'Full rule description'),
            help: SarifMessage(text: 'Rule help text', markdown: '**Rule Help Markdown**'),
          ),
        ],
      );
      expectJsonRoundTrip<SarifDriver>(
        instance: full,
        toJson: (d) => d.toJson(),
        fromJson: SarifDriver.fromJson,
      );

      const minimal = SarifDriver();
      expectJsonRoundTrip<SarifDriver>(
        instance: minimal,
        toJson: (d) => d.toJson(),
        fromJson: SarifDriver.fromJson,
      );

      expect(SarifDriver.fromJson(const {}).name, equals(SarifDriver.defaultDriverName));
    });

    test('SarifDriver negative handling on malformed JSON', () {
      expect(() => SarifDriver.fromJson(const {'name': 123}), throwsA(isA<TypeError>()));
    });

    test('SarifLocation positive round-trip', () {
      const location = SarifLocation(
        physicalLocation: SarifPhysicalLocation(
          artifactLocation: SarifArtifactLocation(uri: 'SKILL.md'),
          region: SarifRegion(startLine: 5, startColumn: 2),
        ),
      );
      expectJsonRoundTrip<SarifLocation>(
        instance: location,
        toJson: (l) => l.toJson(),
        fromJson: SarifLocation.fromJson,
      );
    });

    test('SarifLocation negative handling on malformed JSON', () {
      expect(() => SarifLocation.fromJson(const {}), throwsA(isA<TypeError>()));
    });

    test('SarifLog positive round-trip', () {
      const log = SarifLog(
        runs: [
          SarifRun(
            tool: SarifTool(driver: SarifDriver(name: 'custom_driver')),
          ),
        ],
      );
      expectJsonRoundTrip<SarifLog>(
        instance: log,
        toJson: (l) => l.toJson(),
        fromJson: SarifLog.fromJson,
      );
    });

    test('SarifLog negative handling on malformed JSON', () {
      expect(() => SarifLog.fromJson(const {'runs': 'not_a_list'}), throwsA(isA<TypeError>()));
    });

    test('SarifMessage positive round-trip', () {
      const fullMessage = SarifMessage(
        text: 'Plain text finding',
        markdown: '**Markdown** finding with code `sample`',
      );
      expectJsonRoundTrip<SarifMessage>(
        instance: fullMessage,
        toJson: (m) => m.toJson(),
        fromJson: SarifMessage.fromJson,
      );

      const message = SarifMessage(text: 'Plain text finding');
      expectJsonRoundTrip<SarifMessage>(
        instance: message,
        toJson: (m) => m.toJson(),
        fromJson: SarifMessage.fromJson,
      );

      final defaultMsg = SarifMessage.fromJson(const {});
      expect(defaultMsg.text, isEmpty);
    });

    test('SarifMessage negative handling on malformed JSON', () {
      expect(() => SarifMessage.fromJson(const {'text': 456}), throwsA(isA<TypeError>()));
    });

    test('SarifPhysicalLocation positive round-trip', () {
      const full = SarifPhysicalLocation(
        artifactLocation: SarifArtifactLocation(uri: 'path/to/SKILL.md'),
        region: SarifRegion(startLine: 10, startColumn: 1, endLine: 12, endColumn: 20),
      );
      expectJsonRoundTrip<SarifPhysicalLocation>(
        instance: full,
        toJson: (p) => p.toJson(),
        fromJson: SarifPhysicalLocation.fromJson,
      );

      const minimal = SarifPhysicalLocation(
        artifactLocation: SarifArtifactLocation(uri: 'path/to/SKILL.md'),
      );
      expectJsonRoundTrip<SarifPhysicalLocation>(
        instance: minimal,
        toJson: (p) => p.toJson(),
        fromJson: SarifPhysicalLocation.fromJson,
      );
    });

    test('SarifPhysicalLocation negative handling on malformed JSON', () {
      expect(() => SarifPhysicalLocation.fromJson(const {}), throwsA(isA<TypeError>()));
    });

    test('SarifRegion positive round-trip', () {
      const full = SarifRegion(startLine: 1, startColumn: 2, endLine: 3, endColumn: 4);
      expectJsonRoundTrip<SarifRegion>(
        instance: full,
        toJson: (r) => r.toJson(),
        fromJson: SarifRegion.fromJson,
      );

      const minimal = SarifRegion(startLine: 1);
      expectJsonRoundTrip<SarifRegion>(
        instance: minimal,
        toJson: (r) => r.toJson(),
        fromJson: SarifRegion.fromJson,
      );
    });

    test('SarifRegion negative handling on malformed JSON', () {
      expect(() => SarifRegion.fromJson(const {'startLine': 'one'}), throwsA(isA<TypeError>()));
    });

    test('SarifReportingConfiguration positive round-trip', () {
      const config = SarifReportingConfiguration(level: 'warning');
      expectJsonRoundTrip<SarifReportingConfiguration>(
        instance: config,
        toJson: (c) => c.toJson(),
        fromJson: SarifReportingConfiguration.fromJson,
      );
    });

    test('SarifReportingConfiguration negative handling on malformed JSON', () {
      expect(
        () => SarifReportingConfiguration.fromJson(const {'level': 123}),
        throwsA(isA<TypeError>()),
      );
    });

    test('SarifResult positive round-trip', () {
      const full = SarifResult(
        ruleId: 'valid-yaml-metadata',
        level: 'error',
        message: SarifMessage(text: 'Invalid YAML header'),
        locations: [
          SarifLocation(
            physicalLocation: SarifPhysicalLocation(
              artifactLocation: SarifArtifactLocation(uri: 'SKILL.md'),
              region: SarifRegion(startLine: 1),
            ),
          ),
        ],
        ruleIndex: 0,
      );
      expectJsonRoundTrip<SarifResult>(
        instance: full,
        toJson: (r) => r.toJson(),
        fromJson: SarifResult.fromJson,
      );

      const minimal = SarifResult(
        ruleId: 'valid-yaml-metadata',
        level: 'warning',
        message: SarifMessage(text: 'Minimal failure'),
      );
      expectJsonRoundTrip<SarifResult>(
        instance: minimal,
        toJson: (r) => r.toJson(),
        fromJson: SarifResult.fromJson,
      );
    });

    test('SarifResult negative handling on malformed JSON', () {
      expect(() => SarifResult.fromJson(const {}), throwsA(isA<TypeError>()));
    });

    test('SarifRule positive round-trip', () {
      const full = SarifRule(
        id: 'description-too-long',
        shortDescription: SarifMessage(text: 'Description exceeds length'),
        helpUri: 'https://agentskills.io/specification',
        defaultConfiguration: SarifReportingConfiguration(level: 'error'),
        properties: {
          SarifRule.keyTags: ['lint', 'quality'],
          SarifRule.keyProblemSeverity: 'recommendation',
          SarifRule.keyPrecision: 'very-high',
        },
      );
      expectJsonRoundTrip<SarifRule>(
        instance: full,
        toJson: (r) => r.toJson(),
        fromJson: SarifRule.fromJson,
      );

      const minimal = SarifRule(
        id: 'description-too-long',
        shortDescription: SarifMessage(text: 'Description exceeds length'),
      );
      expectJsonRoundTrip<SarifRule>(
        instance: minimal,
        toJson: (r) => r.toJson(),
        fromJson: SarifRule.fromJson,
      );
    });

    test('SarifRule negative handling on malformed JSON', () {
      expect(() => SarifRule.fromJson(const {}), throwsA(isA<TypeError>()));
    });

    test('SarifRun positive round-trip', () {
      const full = SarifRun(
        tool: SarifTool(driver: SarifDriver(name: 'custom_driver_name')),
        results: [
          SarifResult(
            ruleId: 'valid-yaml-metadata',
            level: 'error',
            message: SarifMessage(text: 'Error'),
          ),
        ],
      );
      expectJsonRoundTrip<SarifRun>(
        instance: full,
        toJson: (r) => r.toJson(),
        fromJson: SarifRun.fromJson,
      );

      const minimal = SarifRun(
        tool: SarifTool(driver: SarifDriver(name: 'custom_minimal_driver')),
      );
      expectJsonRoundTrip<SarifRun>(
        instance: minimal,
        toJson: (r) => r.toJson(),
        fromJson: SarifRun.fromJson,
      );
    });

    test('SarifRun negative handling on malformed JSON', () {
      expect(() => SarifRun.fromJson(const {}), throwsA(isA<TypeError>()));
    });

    test('SarifTool positive round-trip', () {
      const tool = SarifTool(
        driver: SarifDriver(
          name: 'tool_driver',
          version: '2.5.0',
          informationUri: 'https://example.com/docs',
        ),
      );
      expectJsonRoundTrip<SarifTool>(
        instance: tool,
        toJson: (t) => t.toJson(),
        fromJson: SarifTool.fromJson,
      );
    });

    test('SarifTool negative handling on malformed JSON', () {
      expect(() => SarifTool.fromJson(const {}), throwsA(isA<TypeError>()));
    });
  });
}

class _MockCustomRule extends SkillRule {
  @override
  String get name => 'custom-test-rule';

  @override
  AnalysisSeverity get severity => AnalysisSeverity.warning;

  @override
  Future<List<ValidationError>> validate(SkillContext context) async => [];
}
