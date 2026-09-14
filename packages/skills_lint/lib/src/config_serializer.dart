// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Provides formatting of YAML-compatible Dart data structures into YAML strings.
abstract final class ConfigSerializer {
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
