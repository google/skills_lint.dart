// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:meta/meta.dart';

import 'sarif_message.dart';
import 'sarif_reporting_configuration.dart';

/// A reporting descriptor (rule) registered in the tool driver.
@immutable
class SarifRule {
  const SarifRule({
    required this.id,
    required this.shortDescription,
    this.fullDescription,
    this.help,
    this.helpUri,
    this.defaultConfiguration,
    this.properties,
  });

  /// Constructs a [SarifRule] from a JSON map.
  factory SarifRule.fromJson(Map<String, Object?> json) {
    return SarifRule(
      id: json[keyId]! as String,
      shortDescription: SarifMessage.fromJson(json[keyShortDescription]! as Map<String, Object?>),
      fullDescription: json[keyFullDescription] != null
          ? SarifMessage.fromJson(json[keyFullDescription]! as Map<String, Object?>)
          : null,
      help: json[keyHelp] != null
          ? SarifMessage.fromJson(json[keyHelp]! as Map<String, Object?>)
          : null,
      helpUri: json[keyHelpUri] as String?,
      defaultConfiguration: json[keyDefaultConfiguration] != null
          ? SarifReportingConfiguration.fromJson(
              json[keyDefaultConfiguration]! as Map<String, Object?>,
            )
          : null,
      properties: json[keyProperties] != null
          ? Map<String, Object?>.from(json[keyProperties]! as Map)
          : null,
    );
  }

  /// JSON key for [id].
  static const String keyId = 'id';

  /// JSON key for [shortDescription].
  static const String keyShortDescription = 'shortDescription';

  /// JSON key for [fullDescription].
  static const String keyFullDescription = 'fullDescription';

  /// JSON key for [help].
  static const String keyHelp = 'help';

  /// JSON key for [helpUri].
  static const String keyHelpUri = 'helpUri';

  /// JSON key for [defaultConfiguration].
  static const String keyDefaultConfiguration = 'defaultConfiguration';

  /// JSON key for [properties].
  static const String keyProperties = 'properties';

  /// JSON key for [keyTags] within [properties].
  static const String keyTags = 'tags';

  /// JSON key for [keyProblemSeverity] within [properties].
  static const String keyProblemSeverity = 'problem.severity';

  /// JSON key for [keyPrecision] within [properties].
  static const String keyPrecision = 'precision';

  /// The stable, unique identifier for this rule.
  final String id;

  /// A concise single-line description of the rule.
  final SarifMessage shortDescription;

  /// An optional detailed description of the rule, or `null` if omitted.
  final SarifMessage? fullDescription;

  /// Optional rich guidance and remediation examples, or `null` if omitted.
  final SarifMessage? help;

  /// An optional URL pointing to authoritative documentation, or `null` if omitted.
  final String? helpUri;

  /// Default severity configuration for this rule, or `null` if omitted.
  final SarifReportingConfiguration? defaultConfiguration;

  /// Optional property bag containing metadata tags, precision, or severity mappings.
  final Map<String, Object?>? properties;

  /// Converts this rule to a JSON map.
  Map<String, Object?> toJson() => {
    keyId: id,
    keyShortDescription: shortDescription.toJson(),
    if (fullDescription != null) keyFullDescription: fullDescription!.toJson(),
    if (help != null) keyHelp: help!.toJson(),
    if (helpUri != null) keyHelpUri: helpUri,
    if (defaultConfiguration != null) keyDefaultConfiguration: defaultConfiguration!.toJson(),
    if (properties != null) keyProperties: properties,
  };
}
