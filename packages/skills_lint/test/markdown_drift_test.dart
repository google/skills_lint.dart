// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Future<String> _resolvePackageRoot() async {
  final Uri? packageUri = await Isolate.resolvePackageUri(Uri.parse('package:skills_lint/'));
  return packageUri!.resolve('..').toFilePath();
}

void main() {
  group('Markdown documentation sanity', () {
    test('no committed Markdown files contain machine-absolute link targets', () async {
      final String packageRoot = await _resolvePackageRoot();
      final packageDir = Directory(packageRoot);
      final List<File> mdFiles = packageDir
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((File file) => p.extension(file.path) == '.md')
          .where((File file) => !file.path.contains('.dart_tool'))
          .where((File file) => !file.path.contains('third_party'))
          .toList();

      expect(mdFiles, isNotEmpty, reason: 'Expected to find markdown files in package');

      // Check Markdown link targets: [text](link_target)
      final markdownLinkPattern = RegExp(r'\]\(([^)]+)\)');
      final bannedPrefixes = <RegExp>[
        RegExp(r'^file:///Users/'),
        RegExp(r'^file:///home/'),
        RegExp(r'^/Users/[a-zA-Z0-9_-]+/'),
        RegExp(r'^/home/[a-zA-Z0-9_-]+/'),
      ];

      for (final file in mdFiles) {
        final String content = file.readAsStringSync();
        for (final RegExpMatch linkMatch in markdownLinkPattern.allMatches(content)) {
          final String linkTarget = linkMatch.group(1)!.trim();
          for (final pattern in bannedPrefixes) {
            expect(
              pattern.hasMatch(linkTarget),
              isFalse,
              reason:
                  'File "${file.path}" contains machine-absolute link target "$linkTarget". '
                  'Use relative paths instead.',
            );
          }
        }
      }
    });
  });
}
