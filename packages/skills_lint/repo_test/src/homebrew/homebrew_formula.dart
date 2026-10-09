// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'formula_archive.dart';
import 'formula_value.dart';

/// The line that a violation points at when the statement it is about is
/// missing.
const int missingStatementLine = 1;

/// The operating system in a target name, for each block that selects one.
const Map<String, String> _osBlocks = {'on_macos': 'macos', 'on_linux': 'linux'};

/// The architecture in a target name, for each block that selects one.
const Map<String, String> _archBlocks = {'on_arm': 'arm64', 'on_intel': 'x64'};

/// A line that opens a block, such as `on_macos do` or
/// `assert_predicate x do |y|`. Group 1 is the first word.
final RegExp _blockStart = RegExp(r'^(\w+)\b.*\sdo(\s*\|[^|]*\|)?$');

/// A `version`, `url` or `sha256` statement, such as
/// `sha256 "0000…" # PLACEHOLDER`. Group 1 is the keyword and group 2 is the
/// string.
final RegExp _stringStatement = RegExp(r'^(version|url|sha256) "([^"\\]*)"');

/// A macOS dependency, such as `depends_on macos: :sonoma`. Group 1 is the
/// symbol.
final RegExp _macosDependency = RegExp(r'^depends_on macos: :(\w+)');

/// The values in a Homebrew formula that the formula checks compare with the
/// release.
final class HomebrewFormula {
  HomebrewFormula._();

  /// Reads the version, the archives and the macOS dependency of [content].
  ///
  /// It reads only the Ruby that the formula uses: one statement per line,
  /// `do`/`end` blocks, and strings without escapes.
  factory HomebrewFormula.parse(String content) {
    final formula = HomebrewFormula._();
    final List<String> openBlocks = [];
    final List<String> lines = content.split('\n');
    for (var index = 0; index < lines.length; index++) {
      final String line = lines[index].trim();
      final int lineNumber = index + 1;
      // The install and test code that follows holds no values to check.
      if (line.startsWith('def ')) {
        break;
      }
      final RegExpMatch? blockStart = _blockStart.firstMatch(line);
      if (blockStart != null) {
        openBlocks.add(blockStart.group(1)!);
      } else if (line == 'end' && openBlocks.isNotEmpty) {
        openBlocks.removeLast();
      } else {
        formula._readStatement(openBlocks, line, lineNumber);
      }
    }
    return formula;
  }

  FormulaValue? version;

  /// The symbol of `depends_on macos:`, such as `sonoma`.
  FormulaValue? macosMinimum;

  /// Whether [macosMinimum] is inside `on_macos`. Outside it, Homebrew
  /// refuses to install the formula on Linux.
  bool macosMinimumOnMacosOnly = false;

  /// The archives by target, in file order.
  final Map<String, FormulaArchive> archives = {};

  /// Each `url` or `sha256` that no `on_<os>` and `on_<arch>` block pair
  /// encloses.
  final List<FormulaValue> unscopedValues = [];

  /// Every `sha256` of [archives], in file order.
  List<FormulaValue> get sha256s {
    final List<FormulaValue> all = [];
    for (final FormulaArchive archive in archives.values) {
      all.addAll(archive.sha256s);
    }
    return all;
  }

  bool get hasPlaceholders {
    final bool versionIsPlaceholder = version?.placeholder ?? false;
    return versionIsPlaceholder || sha256s.any((FormulaValue sha) => sha.placeholder);
  }

  /// Records [line] if it is a statement that the checks read.
  void _readStatement(List<String> openBlocks, String line, int lineNumber) {
    final bool isPlaceholder = line.contains(placeholderMarker);

    final RegExpMatch? macosDependency = _macosDependency.firstMatch(line);
    if (macosDependency != null) {
      final String symbol = macosDependency.group(1)!;
      macosMinimum = (value: symbol, line: lineNumber, placeholder: isPlaceholder);
      macosMinimumOnMacosOnly = openBlocks.contains('on_macos');
      return;
    }

    final RegExpMatch? statement = _stringStatement.firstMatch(line);
    if (statement == null) {
      return;
    }
    final String keyword = statement.group(1)!;
    final FormulaValue value = (
      value: statement.group(2)!,
      line: lineNumber,
      placeholder: isPlaceholder,
    );
    if (keyword == 'version') {
      version = value;
      return;
    }

    final String? target = _selectedTarget(openBlocks);
    if (target == null) {
      unscopedValues.add(value);
      return;
    }
    final FormulaArchive archive = archives.putIfAbsent(
      target,
      () => FormulaArchive(target, lineNumber),
    );
    if (keyword == 'url') {
      archive.urls.add(value);
    } else {
      archive.sha256s.add(value);
    }
  }
}

/// The `<os>-<arch>` that [openBlocks] select, or null unless they select
/// both an operating system and an architecture.
String? _selectedTarget(List<String> openBlocks) {
  String? os;
  String? arch;
  for (final block in openBlocks) {
    os = _osBlocks[block] ?? os;
    arch = _archBlocks[block] ?? arch;
  }
  if (os == null || arch == null) {
    return null;
  }
  return '$os-$arch';
}
