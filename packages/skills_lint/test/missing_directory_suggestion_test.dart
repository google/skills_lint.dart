// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_lint/src/suggestions/missing_directory_suggestion.dart';
import 'package:test/test.dart';

/// Whether the file system holding [directory] treats names that differ only
/// in case as the same entry.
bool isCaseInsensitive(Directory directory) {
  final probe = Directory(p.join(directory.path, 'case-probe'))..createSync();
  final bool insensitive = Directory(p.join(directory.path, 'CASE-PROBE')).existsSync();
  probe.deleteSync();
  return insensitive;
}

void main() {
  group('suggestDirectory', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('missing_directory_suggestion_test.');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    /// Creates each of [directories] under the temporary directory.
    void createAll(List<String> directories) {
      for (final directory in directories) {
        Directory(p.join(tempDir.path, directory)).createSync(recursive: true);
      }
    }

    /// Suggests a directory for [declared], anchored to [anchor] under the
    /// temporary directory, with the temporary directory as the working
    /// directory.
    String? suggest(String declared, {String anchor = ''}) {
      final String base = p.normalize(p.join(tempDir.path, anchor));
      return suggestDirectory(
        declaredText: declared,
        resolvedPath: p.normalize(p.join(base, declared)),
        baseDirectory: base,
        workingDirectory: tempDir.path,
      );
    }

    final cases =
        <({String name, String declared, String anchor, List<String> onDisk, String? expected})>[
          (
            name: 'the last folder is misspelled',
            declared: '.agents/skill',
            anchor: '',
            onDisk: ['.agents/skills'],
            expected: '.agents/skills',
          ),
          (
            name: 'an intermediate folder is misspelled',
            declared: '.agent/skills',
            anchor: '',
            onDisk: ['.agents/skills'],
            expected: '.agents/skills',
          ),
          (
            name: 'the path resolved from the configuration directory, not the working directory',
            declared: '.agents/skills',
            anchor: 'tool',
            onDisk: ['.agents/skills', 'tool'],
            expected: '../.agents/skills',
          ),
          (
            name: 'two folders are misspelled',
            declared: '.agent/skils',
            anchor: '',
            onDisk: ['.agents/skills'],
            expected: null,
          ),
          (
            name: 'two candidates are equally close',
            declared: 'skills',
            anchor: '',
            onDisk: ['skill', 'skillz'],
            expected: null,
          ),
        ];

    for (final c in cases) {
      test('${c.expected == null ? 'suggests nothing' : 'suggests "${c.expected}"'} '
          'when ${c.name}', () {
        createAll(c.onDisk);
        expect(suggest(c.declared, anchor: c.anchor), c.expected);
      });
    }

    test('suggests the correctly cased folder on a case-sensitive file system', () {
      createAll(['.agents/skills']);
      if (isCaseInsensitive(tempDir)) {
        markTestSkipped('The file system ignores case, so ".Agents/skills" exists.');
        return;
      }
      expect(suggest('.Agents/skills'), '.agents/skills');
    });
  });
}
