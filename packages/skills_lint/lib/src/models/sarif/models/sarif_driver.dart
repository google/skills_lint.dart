// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'sarif_rule.dart';

/// The primary tool component (driver) that produced the analysis results.
class SarifDriver {
  SarifDriver({
    this.name = defaultDriverName,
    this.version = defaultDriverVersion,
    this.informationUri = defaultInformationUri,
    this.rules = const [],
  });

  /// Constructs a [SarifDriver] from a JSON map.
  factory SarifDriver.fromJson(Map<String, Object?> json) {
    return SarifDriver(
      name: (json[keyName] ?? defaultDriverName) as String,
      version: json[keyVersion] as String?,
      informationUri: json[keyInformationUri] as String?,
      rules:
          (json[keyRules] as List<Object?>?)
              ?.map((r) => SarifRule.fromJson(r! as Map<String, Object?>))
              .toList() ??
          [],
    );
  }

  /// JSON key for [name].
  static const String keyName = 'name';

  /// JSON key for [version].
  static const String keyVersion = 'version';

  /// JSON key for [informationUri].
  static const String keyInformationUri = 'informationUri';

  /// JSON key for [rules].
  static const String keyRules = 'rules';

  static const String defaultDriverName = 'skills_lint';
  static const String defaultDriverVersion = '0.5.2';
  static const String defaultInformationUri = 'https://github.com/google/skills_lint.dart';

  /// The name of the tool component, as displayed by SARIF consumers.
  ///
  /// For `skills_lint` this is the string a reader sees identifying which tool
  /// produced a finding, in a report that may aggregate several analyzers.
  final String name;

  /// The version of the tool component.
  final String? version;

  /// The URI of the tool component's documentation or homepage.
  final String? informationUri;

  /// The rules provided by this tool component.
  final List<SarifRule> rules;

  /// Converts this driver to a JSON map.
  Map<String, Object?> toJson() => {
    keyName: name,
    if (version != null) keyVersion: version,
    if (informationUri != null) keyInformationUri: informationUri,
    if (rules.isNotEmpty) keyRules: rules.map((r) => r.toJson()).toList(),
  };
}
