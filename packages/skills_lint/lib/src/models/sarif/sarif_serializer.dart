// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;

import '../../rule_registry.dart';
import '../analysis_severity.dart';
import '../check_type.dart';
import '../skill_context.dart';
import '../skill_rule.dart';
import '../source_region.dart';
import '../validation_error.dart';
import '../validation_result.dart';
import 'models/models.dart';

/// Serializes validation results into OASIS SARIF 2.1.0 document format.
class SarifSerializer {
  /// Converts an [AnalysisSeverity] to the corresponding SARIF 2.1.0 level string.
  ///
  /// * `AnalysisSeverity.error` -> `'error'`
  /// * `AnalysisSeverity.warning` -> `'warning'`
  /// * `AnalysisSeverity.disabled` -> `'none'`
  static String severityToSarifLevel(AnalysisSeverity severity) {
    switch (severity) {
      case AnalysisSeverity.error:
        return 'error';
      case AnalysisSeverity.warning:
        return 'warning';
      case AnalysisSeverity.disabled:
        return 'none';
    }
  }

  /// Builds a [SarifLog] from a list of [ValidationResult]s.
  static SarifLog toSarifLog(
    List<ValidationResult> results, {
    String toolVersion = SarifDriver.defaultDriverVersion,
    List<CheckType>? checkTypes,
    List<SkillRule>? customRules,
  }) {
    _gitRootCache ??= _findGitRoot() ?? Directory.current.path;
    final List<SarifRule> rules = _buildSarifRules(
      checkTypes ?? RuleRegistry.allChecks,
      customRules ?? [],
    );
    final ruleIndexMap = <String, int>{for (var i = 0; i < rules.length; i++) rules[i].id: i};

    final sarifResults = <SarifResult>[];
    for (final result in results) {
      for (final ValidationError error in result.validationErrors) {
        if (error.isIgnored || error.severity == AnalysisSeverity.disabled) {
          continue;
        }
        sarifResults.add(_buildSarifResult(error, result.context, ruleIndexMap));
      }
    }

    final driver = SarifDriver(version: toolVersion, rules: rules);

    return SarifLog(
      runs: [
        SarifRun(
          tool: SarifTool(driver: driver),
          results: sarifResults,
          originalUriBaseIds: {
            '%SRCROOT%': {
              'uri': Uri.directory(_gitRootCache ?? Directory.current.path).toString(),
              'description': {'text': 'The root directory for all project files.'},
            },
          },
        ),
      ],
    );
  }

  static List<SarifRule> _buildSarifRules(List<CheckType> checks, List<SkillRule> customRules) {
    final rules = <SarifRule>[];
    final seen = <String>{};

    for (final check in checks) {
      if (!seen.contains(check.name)) {
        seen.add(check.name);
        rules.add(
          SarifRule(
            id: check.name,
            shortDescription: SarifMessage(text: check.help),
            helpUri: SarifDriver.defaultInformationUri,
            defaultConfiguration: SarifReportingConfiguration(
              level: severityToSarifLevel(check.defaultSeverity),
            ),
            properties: {
              SarifRule.keyTags: const ['lint', 'quality'],
              SarifRule.keyProblemSeverity: 'recommendation',
              SarifRule.keyPrecision: 'very-high',
            },
          ),
        );
      }
    }

    for (final customRule in customRules) {
      if (!seen.contains(customRule.name)) {
        seen.add(customRule.name);
        rules.add(
          SarifRule(
            id: customRule.name,
            shortDescription: SarifMessage(text: 'Custom rule ${customRule.name}.'),
            helpUri: SarifDriver.defaultInformationUri,
            defaultConfiguration: SarifReportingConfiguration(
              level: severityToSarifLevel(customRule.severity),
            ),
            properties: {
              SarifRule.keyTags: const ['lint', 'quality', 'custom-rule'],
              SarifRule.keyProblemSeverity: 'recommendation',
              SarifRule.keyPrecision: 'very-high',
            },
          ),
        );
      }
    }

    return rules;
  }

  static SarifResult _buildSarifResult(
    ValidationError error,
    SkillContext? context,
    Map<String, int> ruleIndexMap,
  ) {
    final String uri = _resolveUri(error, context);
    final SarifRegion region = _resolveRegion(error);

    return SarifResult(
      ruleId: error.ruleId,
      level: severityToSarifLevel(error.severity),
      message: SarifMessage(text: error.message, markdown: error.markdownMessage),
      ruleIndex: ruleIndexMap[error.ruleId],
      locations: [
        SarifLocation(
          physicalLocation: SarifPhysicalLocation(
            artifactLocation: SarifArtifactLocation(uri: uri, uriBaseId: '%SRCROOT%'),
            region: region,
          ),
        ),
      ],
    );
  }

  static SarifRegion _resolveRegion(ValidationError error) {
    final SourceRegion? region = error.region;
    if (region != null) {
      return SarifRegion(
        startLine: region.startLine,
        startColumn: region.startColumn,
        endLine: region.endLine,
        endColumn: region.endColumn,
      );
    }
    return SarifRegion(startLine: 1);
  }

  static String? _gitRootCache;

  static String? _findGitRoot() {
    if (_gitRootCache != null) {
      return _gitRootCache;
    }
    try {
      final ProcessResult result = Process.runSync('git', ['rev-parse', '--show-toplevel']);
      if (result.exitCode == 0) {
        _gitRootCache = result.stdout.toString().trim();
        return _gitRootCache;
      }
    } catch (_) {}
    return null;
  }

  static String _resolveUri(ValidationError error, SkillContext? context) {
    String rawPath;
    if (context != null) {
      final String dirPath = context.directory.path;
      if (error.file == SkillContext.skillFileName) {
        rawPath = p.join(dirPath, error.file);
      } else if (p.equals(dirPath, error.file) || p.isWithin(dirPath, error.file)) {
        rawPath = error.file;
      } else if (p.isAbsolute(error.file)) {
        rawPath = error.file;
      } else {
        rawPath = p.join(dirPath, error.file);
      }
    } else {
      rawPath = error.file;
    }

    final String absolutePath = p.absolute(rawPath);
    final String? root = _findGitRoot();
    if (root != null && p.isWithin(root, absolutePath)) {
      return p.toUri(p.relative(absolutePath, from: root)).toString();
    }
    if (p.isWithin(Directory.current.path, absolutePath)) {
      return p.toUri(p.relative(absolutePath, from: Directory.current.path)).toString();
    }
    if (context != null && p.isWithin(context.directory.parent.path, absolutePath)) {
      return p.toUri(p.relative(absolutePath, from: context.directory.parent.path)).toString();
    }
    if (!p.isAbsolute(rawPath)) {
      return p.toUri(rawPath).toString();
    }
    return p.toUri(absolutePath).toString();
  }
}
