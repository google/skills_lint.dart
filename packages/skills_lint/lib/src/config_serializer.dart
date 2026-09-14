// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'config_parser.dart';
import 'models/custom_rule_parameters.dart';
import 'models/rule_config.dart';

/// Provides programmatic YAML serialization for linter configurations and rule settings.
abstract final class ConfigSerializer {
  /// Converts a [Configuration] into its YAML map representation.
  static Map<String, Object?> configToYamlMap(Configuration config) {
    final skillsLintMap = <String, Object?>{};

    if (config.ruleConfigs.isNotEmpty) {
      skillsLintMap[ConfigParser.rulesKey] = <String, Object?>{
        for (final MapEntry<String, RuleConfigPatch> entry in config.ruleConfigs.entries)
          entry.key: ruleConfigPatchToYaml(entry.value),
      };
    }

    if (config.directoryConfigs.isNotEmpty) {
      skillsLintMap[ConfigParser.directoriesKey] = <Map<String, Object?>>[
        for (final LintTargetConfig dir in config.directoryConfigs) targetConfigToYamlMap(dir),
      ];
    }

    if (config.individualSkillConfigs.isNotEmpty) {
      skillsLintMap[ConfigParser.individualSkillsKey] = <Map<String, Object?>>[
        for (final LintTargetConfig skill in config.individualSkillConfigs)
          targetConfigToYamlMap(skill),
      ];
    }

    return <String, Object?>{ConfigParser.skillsLintKey: skillsLintMap};
  }

  /// Converts a [Configuration] into a formatted YAML string.
  static String configToYamlString(Configuration config) {
    return toYamlString(configToYamlMap(config));
  }

  /// Converts a [LintTargetConfig] into its YAML map representation.
  static Map<String, Object?> targetConfigToYamlMap(LintTargetConfig config) {
    final map = <String, Object?>{ConfigParser.pathKey: config.path};

    if (config.ruleConfigs.isNotEmpty) {
      map[ConfigParser.rulesKey] = <String, Object?>{
        for (final MapEntry<String, RuleConfigPatch> entry in config.ruleConfigs.entries)
          entry.key: ruleConfigPatchToYaml(entry.value),
      };
    }

    if (config.ignoreFile != null) {
      map[ConfigParser.ignoreFileKey] = config.ignoreFile;
    }

    return map;
  }

  /// Converts a [LintTargetConfig] into a formatted YAML string.
  static String targetConfigToYamlString(LintTargetConfig config) {
    return toYamlString(targetConfigToYamlMap(config));
  }

  /// Converts a [RuleConfigPatch] into its YAML value (either a String severity or a Map).
  static Object? ruleConfigPatchToYaml(RuleConfigPatch patch) {
    final bool hasParams = patch.parameters != null && patch.parameters!.isNotEmpty;
    if (!hasParams) {
      if (patch.severity != null) {
        return patch.severity!.name;
      }
      return <String, Object?>{};
    }
    return ruleConfigPatchToYamlMap(patch);
  }

  /// Converts a [RuleConfigPatch] into a YAML map representation.
  static Map<String, Object?> ruleConfigPatchToYamlMap(RuleConfigPatch patch) {
    final map = <String, Object?>{};
    if (patch.parameters != null && patch.parameters!.isNotEmpty) {
      for (final MapEntry<String, Object?> entry in patch.parameters!.params.entries) {
        if (entry.key != ConfigParser.severityKey) {
          map[entry.key] = entry.value;
        }
      }
    }
    if (patch.severity != null) {
      map[ConfigParser.severityKey] = patch.severity!.name;
    }
    return map;
  }

  /// Converts a [RuleConfigPatch] into a formatted YAML string.
  static String ruleConfigPatchToYamlString(RuleConfigPatch patch) {
    return toYamlString(ruleConfigPatchToYaml(patch));
  }

  /// Converts a [RuleConfig] into its YAML value (either a String severity or a Map).
  static Object ruleConfigToYaml(RuleConfig config) {
    if (config.parameters.isEmpty) {
      return config.severity.name;
    }
    return ruleConfigToYamlMap(config);
  }

  /// Converts a [RuleConfig] into a YAML map representation.
  static Map<String, Object?> ruleConfigToYamlMap(RuleConfig config) {
    final map = <String, Object?>{};
    if (config.parameters.isNotEmpty) {
      for (final MapEntry<String, Object?> entry in config.parameters.params.entries) {
        if (entry.key != ConfigParser.severityKey) {
          map[entry.key] = entry.value;
        }
      }
    }
    map[ConfigParser.severityKey] = config.severity.name;
    return map;
  }

  /// Converts a [RuleConfig] into a formatted YAML string.
  static String ruleConfigToYamlString(RuleConfig config) {
    return toYamlString(ruleConfigToYaml(config));
  }

  /// Converts a [CustomRuleParameters] into a formatted YAML string.
  static String customRuleParametersToYamlString(CustomRuleParameters parameters) {
    return toYamlString(parameters.toYamlMap());
  }

  /// Converts a YAML-compatible Dart primitive structure into a formatted YAML string.
  static String toYamlString(Object? value) {
    final emitter = _YamlEmitter();
    emitter.write(value);
    return emitter.toString();
  }
}

/// Recursive emitter that generates deterministic, formatted YAML strings
/// from structured Dart data representations (Maps, Lists, and scalar primitives).
class _YamlEmitter {
  final StringBuffer _buffer = StringBuffer();

  /// Formats and writes [value] as YAML into the internal buffer.
  void write(Object? value) {
    if (value is Map) {
      _writeMap(value, 0);
    } else if (value is List) {
      _writeList(value, 0);
    } else {
      _buffer.writeln(_formatScalar(value));
    }
  }

  void _writeMap(Map<dynamic, dynamic> map, int indentLevel) {
    if (map.isEmpty) {
      _buffer.writeln('${_indent(indentLevel)}{}');
      return;
    }
    for (final MapEntry<dynamic, dynamic> entry in map.entries) {
      final String keyStr = _formatKey(entry.key.toString());
      final Object? val = entry.value;
      if (val is Map && val.isNotEmpty) {
        _buffer.writeln('${_indent(indentLevel)}$keyStr:');
        _writeMap(val, indentLevel + 1);
      } else if (val is List && val.isNotEmpty) {
        _buffer.writeln('${_indent(indentLevel)}$keyStr:');
        _writeList(val, indentLevel + 1);
      } else {
        _buffer.writeln('${_indent(indentLevel)}$keyStr: ${_formatScalar(val)}');
      }
    }
  }

  void _writeList(List<dynamic> list, int indentLevel) {
    if (list.isEmpty) {
      _buffer.writeln('${_indent(indentLevel)}[]');
      return;
    }
    for (final Object? item in list) {
      if (item is Map && item.isNotEmpty) {
        _writeListMapItem(item, indentLevel);
      } else if (item is List && item.isNotEmpty) {
        _buffer.writeln('${_indent(indentLevel)}-');
        _writeList(item, indentLevel + 1);
      } else {
        _buffer.writeln('${_indent(indentLevel)}- ${_formatScalar(item)}');
      }
    }
  }

  void _writeListMapItem(Map<dynamic, dynamic> map, int indentLevel) {
    var isFirst = true;
    for (final MapEntry<dynamic, dynamic> entry in map.entries) {
      final String keyStr = _formatKey(entry.key.toString());
      final Object? val = entry.value;
      final prefix = isFirst ? '${_indent(indentLevel)}- ' : '${_indent(indentLevel)}  ';
      isFirst = false;

      if (val is Map && val.isNotEmpty) {
        _buffer.writeln('$prefix$keyStr:');
        _writeMap(val, indentLevel + 2);
      } else if (val is List && val.isNotEmpty) {
        _buffer.writeln('$prefix$keyStr:');
        _writeList(val, indentLevel + 2);
      } else {
        _buffer.writeln('$prefix$keyStr: ${_formatScalar(val)}');
      }
    }
  }

  String _indent(int level) => '  ' * level;

  String _formatScalar(Object? value) {
    if (value == null) {
      return 'null';
    }
    if (value is bool) {
      return value ? 'true' : 'false';
    }
    if (value is num) {
      return value.toString();
    }
    if (value is String) {
      return _formatString(value);
    }
    if (value is Map && value.isEmpty) {
      return '{}';
    }
    if (value is List && value.isEmpty) {
      return '[]';
    }
    return _formatString(value.toString());
  }

  static final RegExp _safeUnquotedPattern = RegExp(r'^[a-zA-Z_][a-zA-Z0-9_/.-]*$');

  /// Reserved boolean, null, and special literal tokens per the YAML 1.2.2
  /// Core Schema specification (https://yaml.org/spec/1.2.2/#10214-core-schema)
  /// that require quoting to prevent unintended type coercion during YAML parsing.
  static const Set<String> _yamlKeywords = {'true', 'false', 'null', '~'};

  static bool _shouldQuote(String value) {
    if (value.isEmpty) {
      return true;
    }
    final String lower = value.toLowerCase();
    if (_yamlKeywords.contains(lower)) {
      return true;
    }
    if (!_safeUnquotedPattern.hasMatch(value)) {
      return true;
    }
    return false;
  }

  String _formatKey(String key) {
    if (_shouldQuote(key)) {
      return _escapeYamlString(key);
    }
    return key;
  }

  String _formatString(String value) {
    if (_shouldQuote(value)) {
      return _escapeYamlString(value);
    }
    return value;
  }

  String _escapeYamlString(String value) {
    final buffer = StringBuffer('"');
    for (var i = 0; i < value.length; i++) {
      final int codeUnit = value.codeUnitAt(i);
      switch (codeUnit) {
        case 0x5C: // \
          buffer.write(r'\\');
        case 0x22: // "
          buffer.write(r'\"');
        case 0x0A: // \n
          buffer.write(r'\n');
        case 0x0D: // \r
          buffer.write(r'\r');
        case 0x09: // \t
          buffer.write(r'\t');
        case 0x08: // \b
          buffer.write(r'\b');
        case 0x0C: // \f
          buffer.write(r'\f');
        default:
          if (codeUnit < 0x20 || codeUnit == 0x7F) {
            buffer.write(r'\x');
            buffer.write(codeUnit.toRadixString(16).padLeft(2, '0'));
          } else {
            buffer.writeCharCode(codeUnit);
          }
      }
    }
    buffer.write('"');
    return buffer.toString();
  }

  @override
  String toString() => _buffer.toString();
}
