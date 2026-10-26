// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:test/test.dart';

/// The longest bullet allowed in the top CHANGELOG section.
///
/// This is a proxy. The goal is that each entry tells a user what they need
/// to know about a change, briefly. An entry longer than this is likely
/// carrying detail that belongs in the docs or the pull request.
const int maxBulletLength = 300;

/// The `### ` headings allowed in a `-wip` section, in the order they must appear.
///
/// CONTRIBUTING.md says what belongs under each one.
const List<String> sectionHeadings = [
  'Breaking changes',
  'New rules',
  'Behavior changes',
  'New features',
  'Bug fixes',
];

/// Checks the top CHANGELOG section.
///
/// Only the section under the first `## ` heading is checked. Released
/// sections are not rewritten, so they are not checked. Each entry is a
/// `- ` bullet. In a `-wip` section, each bullet sits under one of the
/// [sectionHeadings].
void main() {
  final List<String> lines = File('CHANGELOG.md').readAsLinesSync();
  final int start = lines.indexWhere((String l) => l.startsWith('## '));
  final String heading = start == -1 ? '' : lines[start].substring(3).trim();
  final List<String> section = start == -1
      ? const []
      : lines.skip(start + 1).takeWhile((String l) => !l.startsWith('## ')).toList();

  test('CHANGELOG has a version heading', () {
    expect(start, isNot(-1), reason: 'CHANGELOG.md has no "## " version heading.');
  });

  test('top CHANGELOG section entries tell users only what they need', () {
    final List<String> long = [
      for (final String bullet in _bullets(section))
        if (bullet.length > maxBulletLength) bullet,
    ];
    expect(
      long,
      isEmpty,
      reason:
          'These entries in the "$heading" section of CHANGELOG.md are longer than '
          '$maxBulletLength characters. Shorten each one to what a user needs to know '
          'about the change, and move the rest of the detail to the docs or the pull '
          'request:\n'
          '${long.map(_preview).join('\n')}',
    );
  });

  test('-wip CHANGELOG section groups entries under the listed headings', () {
    if (!heading.endsWith('-wip')) {
      markTestSkipped('The top section, "$heading", is released.');
      return;
    }
    final List<String> problems = _headingProblems(section);
    expect(
      problems,
      isEmpty,
      reason:
          'The "$heading" section of CHANGELOG.md must put each entry under one of '
          'these "### " headings, in this order, each at most once, leaving out empty '
          'ones: ${sectionHeadings.join(', ')}. See "Changelog sections" in '
          'CONTRIBUTING.md.\n'
          '${problems.join('\n')}',
    );
  });

  group('heading check', () {
    test('accepts headings in order with entries under each', () {
      expect(_headingProblems(['### New rules', '- a', '### Bug fixes', '- b']), isEmpty);
    });
    test('reports an unknown heading', () {
      expect(_headingProblems(['### Misc', '- a']), [contains('not one of the headings')]);
    });
    test('reports headings out of order', () {
      expect(_headingProblems(['### Bug fixes', '- a', '### New rules', '- b']), [
        contains('out of order'),
      ]);
    });
    test('reports a repeated heading', () {
      expect(_headingProblems(['### New rules', '- a', '### New rules', '- b']), [
        contains('repeated'),
      ]);
    });
    test('reports an empty heading', () {
      expect(_headingProblems(['### New rules', '', '### Bug fixes', '- b']), [
        contains('has no entries'),
      ]);
    });
    test('reports an entry before any heading', () {
      expect(_headingProblems(['- a', '### Bug fixes', '- b']), [contains('not under a heading')]);
    });
  });
}

/// Returns a description of each heading problem in [section].
List<String> _headingProblems(List<String> section) {
  final problems = <String>[];
  var lastIndex = -1;
  String? current;
  var currentHasBullets = false;
  void closeHeading() {
    if (current != null && !currentHasBullets) {
      problems.add('- "### $current" has no entries. Leave it out.');
    }
  }

  for (final line in section) {
    if (line.startsWith('#')) {
      closeHeading();
      current = line.startsWith('### ') ? line.substring(4).trim() : line;
      currentHasBullets = false;
      final int index = sectionHeadings.indexOf(current);
      if (index == -1) {
        problems.add('- "$line" is not one of the headings.');
      } else if (index <= lastIndex) {
        problems.add('- "$line" is out of order or repeated.');
      } else {
        lastIndex = index;
      }
    } else if (line.startsWith('- ')) {
      if (current == null) {
        problems.add('${_preview(line.substring(2).trim())} is not under a heading.');
      }
      currentHasBullets = true;
    }
  }
  closeHeading();
  return problems;
}

/// Returns the bullets in [lines], joining wrapped lines.
///
/// `### ` headings end the bullet before them.
List<String> _bullets(Iterable<String> lines) {
  final bullets = <String>[];
  var inBullet = false;
  for (final line in lines) {
    if (line.startsWith('- ')) {
      bullets.add(line.substring(2).trim());
      inBullet = true;
    } else if (line.startsWith('#')) {
      inBullet = false;
    } else if (line.trim().isNotEmpty && inBullet) {
      bullets.last = '${bullets.last} ${line.trim()}';
    }
  }
  return bullets;
}

String _preview(String bullet) =>
    '- (${bullet.length} chars) "${bullet.length > 80 ? '${bullet.substring(0, 80)}...' : bullet}"';
