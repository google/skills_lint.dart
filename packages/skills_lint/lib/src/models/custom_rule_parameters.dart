// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:meta/meta.dart';

import '../config_serializer.dart';

/// A wrapper around raw rule parameters.
///
/// Prevents exposing raw [Map] APIs directly inside rule logic, and provides
/// standard lookups and properties for rule configuration parameters.
@immutable
class CustomRuleParameters {
  /// Creates a new configuration with the provided [params].
  CustomRuleParameters([Map<String, Object?>? params])
    : params = params != null
          ? Map<String, Object?>.unmodifiable(
              params.map((String k, Object? v) => MapEntry(k, _deepUnmodifiable(v))),
            )
          : const <String, Object?>{};

  /// Constant constructor for an empty parameters object.
  const CustomRuleParameters.empty() : params = const <String, Object?>{};

  static Object? _deepUnmodifiable(Object? value) {
    if (value is Map) {
      return Map<String, Object?>.unmodifiable(
        value.map((Object? k, Object? v) => MapEntry(k.toString(), _deepUnmodifiable(v))),
      );
    }
    if (value is List) {
      return List<Object?>.unmodifiable(value.map(_deepUnmodifiable));
    }
    return value;
  }

  /// The underlying map containing the parameters.
  final Map<String, Object?> params;

  bool get isEmpty => params.isEmpty;

  bool get isNotEmpty => params.isNotEmpty;

  Object? operator [](String key) => params[key];

  Iterable<String> get keys => params.keys;

  bool containsKey(String key) => params.containsKey(key);

  /// Converts this parameters object into its YAML map representation.
  Map<String, Object?> toYamlMap() => Map<String, Object?>.from(params);

  /// Converts this parameters object into its YAML representation.
  Map<String, Object?> toYaml() => toYamlMap();

  /// Converts this parameters object into a formatted YAML string.
  String toYamlString() => ConfigSerializer.toYamlString(params);

  /// Retrieves the value of the parameter associated with [key] as a [String].
  ///
  /// Returns `null` if the value is missing or not a [String].
  String? getString(String key) {
    final Object? val = params[key];
    return val is String ? val : null;
  }

  /// Retrieves the value of the parameter associated with [key] as an [int].
  ///
  /// Returns `null` if the value is missing or not an [int].
  int? getInt(String key) {
    final Object? val = params[key];
    return val is int ? val : null;
  }

  /// Retrieves the value of the parameter associated with [key] as a [bool].
  ///
  /// Returns `null` if the value is missing or not a [bool].
  bool? getBool(String key) {
    final Object? val = params[key];
    return val is bool ? val : null;
  }

  /// Retrieves the value of the parameter associated with [key] as a [List] of [String]s.
  ///
  /// Returns `null` if the value is missing or not a [List].
  List<String>? getStringList(String key) {
    final Object? val = params[key];
    if (val is List) {
      return val.map((Object? e) => e.toString()).toList();
    }
    return null;
  }
}
