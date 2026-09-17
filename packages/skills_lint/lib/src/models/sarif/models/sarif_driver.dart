// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:meta/meta.dart';

import 'sarif_rule.dart';

/// The primary tool component (driver) that produced analysis results.
///
/// In the OASIS SARIF 2.1.0 specification (§3.18.2), the `driver` component
/// describes the executable or core plugin that orchestrated the analysis run
/// (such as `skills_lint`). The driver specifies the tool name, optional version,
/// documentation URI, and rule definitions.
@immutable
class SarifDriver {
  const SarifDriver({
    this.name = defaultDriverName,
    this.version,
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

  /// The default driver tool name ('skills_lint').
  static const String defaultDriverName = 'skills_lint';

  /// The default documentation and homepage URI.
  static const String defaultInformationUri = 'https://github.com/google/skills_lint.dart';

  /// The display name of the tool component.
  final String name;

  /// The version of the tool component, or `null` if unspecified.
  final String? version;

  /// The homepage or documentation URI of the tool component.
  final String? informationUri;

  /// The catalog of rules provided by this tool component.
  final List<SarifRule> rules;

  /// Converts this driver to a JSON map.
  Map<String, Object?> toJson() => {
    keyName: name,
    if (version != null) keyVersion: version,
    if (informationUri != null) keyInformationUri: informationUri,
    if (rules.isNotEmpty) keyRules: rules.map((r) => r.toJson()).toList(),
  };
}
