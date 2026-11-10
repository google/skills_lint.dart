// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import '../models/config_notification.dart';
import '../models/sarif/models/models.dart';
import '../models/sarif/sarif_serializer.dart';
import '../models/skill_rule.dart';
import '../models/validation_result.dart';
import '../rule_registry.dart';
import 'reporter.dart';

/// SARIF 2.1.0 document reporter for CI and GitHub Code Scanning.
class SarifReporter extends Reporter {
  SarifReporter({super.out, super.err, this.pretty = true, this.toolVersion});

  final bool pretty;
  final String? toolVersion;

  @override
  void onSessionComplete(
    List<ValidationResult> results, {
    List<SkillRule> customRules = const [],
    List<ConfigNotification> configNotifications = const [],
  }) {
    final SarifLog sarif = SarifSerializer.toSarifLog(
      results,
      toolVersion: toolVersion,
      checkTypes: RuleRegistry.allChecks,
      customRules: customRules,
      configNotifications: configNotifications,
    );
    final encoder = pretty ? const JsonEncoder.withIndent('  ') : const JsonEncoder();
    out.writeln(encoder.convert(sarif.toJson()));
  }
}
