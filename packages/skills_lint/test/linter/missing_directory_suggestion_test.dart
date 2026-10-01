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

/// Creates a symlink at [link] pointing to [target], returning `false` when
/// this platform cannot create one here.
bool tryCreateLink(String link, String target) {
  try {
    Link(link).createSync(target);
    return true;
  } on FileSystemException {
    return false;
  }
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

    test('writes a portable relative suggestion when the anchor is spelled through a symlink', () {
      final real = Directory(p.join(tempDir.path, 'real'));
      Directory(p.join(real.path, '.agents', 'skills')).createSync(recursive: true);
      Directory(p.join(real.path, 'tool')).createSync();
      final String linked = p.join(tempDir.path, 'linked');
      if (!tryCreateLink(linked, real.path)) {
        markTestSkipped('This platform cannot create a directory symlink here.');
        return;
      }

      // The configuration is named through the link; the working directory is
      // reported by the operating system as its physical path.
      final String anchor = p.join(linked, 'tool');
      expect(
        suggestDirectory(
          declaredText: '.agents/skills',
          resolvedPath: p.join(anchor, '.agents', 'skills'),
          baseDirectory: anchor,
          workingDirectory: real.resolveSymbolicLinksSync(),
        ),
        '../.agents/skills',
      );
    });

    group('for a path under the home directory', () {
      late String home;

      setUp(() {
        home = p.join(tempDir.path, 'home');
        createAll(['home/.agents/skills', 'elsewhere/skills']);
      });

      /// Suggests a directory for [declared], expanding `~` to [home].
      String? suggestFromHome(String declared) => suggestDirectory(
        declaredText: declared,
        resolvedPath: p.normalize(p.join(home, declared.substring(2))),
        baseDirectory: tempDir.path,
        homeDirectory: home,
      );

      test('keeps the "~/" form the author wrote', () {
        expect(suggestFromHome('~/.agent/skills'), '~/.agents/skills');
      });

      test('writes an absolute suggestion when the match is outside the home directory', () {
        expect(
          suggestFromHome('~/../elsewhere/skils'),
          p.join(tempDir.path, 'elsewhere', 'skills'),
        );
      });
    });

    test('returns normally when a probed directory cannot be read', () {
      createAll(['locked/skills']);
      final String locked = p.join(tempDir.path, 'locked');
      Process.runSync('chmod', ['000', locked]);
      addTearDown(() => Process.runSync('chmod', ['755', locked]));

      // "lockd" is one edit from "locked", so the suggestion probes
      // "locked/skills", which the operating system refuses to stat.
      expect(() => suggest('lockd/skills'), returnsNormally);
    }, testOn: '!windows');

    test('suggests a lexical path from a configuration directory linked elsewhere', () {
      createAll(['repo/.agents/skills', 'a/b/c/shared-tool']);
      // Run from the repository, as the operating system reports it, with the
      // configuration in "tool", which links to "a/b/c/shared-tool".
      final String repo = Directory(p.join(tempDir.path, 'repo')).resolveSymbolicLinksSync();
      final String anchor = p.join(repo, 'tool');
      if (!tryCreateLink(anchor, p.join(tempDir.path, 'a', 'b', 'c', 'shared-tool'))) {
        markTestSkipped('This platform cannot create a directory symlink here.');
        return;
      }

      // The tool resolves "../.agents/skills" from "repo/tool" lexically, so
      // the suggestion must not walk up from the link's physical target.
      expect(
        suggestDirectory(
          declaredText: '.agents/skills',
          resolvedPath: p.join(anchor, '.agents', 'skills'),
          baseDirectory: anchor,
          workingDirectory: repo,
        ),
        '../.agents/skills',
      );
    });

    test('treats a name that merely starts with "~" as relative', () {
      createAll(['~foo/skills']);
      expect(suggest('~foo/skils'), '~foo/skills');
    });
  });
}
