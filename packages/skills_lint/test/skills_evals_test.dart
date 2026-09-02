// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Optional item keys permitted across all `evals.json` and rubric files.
/// Maintainers can add optional keys to this set.
const Set<String> optionalItemKeys = {'agent_config', 'test_data'};

void main() {
  group('Evals structure consistency', () {
    // Ensures all evals.json files dynamically share consistent JSON schema.
    // Keys are not hardcoded to ensure enforcement remains schema-agnostic and flexible.
    test('all evals.json files across skills share consistent structure and keys', () async {
      final Uri? packageUri = await Isolate.resolvePackageUri(Uri.parse('package:skills_lint/'));
      final String packageRoot = packageUri!.resolve('..').toFilePath();

      final List<File> evalsFiles = [
        ..._findEvalsFiles(Directory(p.join(packageRoot, 'skills'))),
        ..._findEvalsFiles(
          Directory(p.normalize(p.join(packageRoot, '..', '..', '.agents', 'skills'))),
        ),
        ..._findEvalsFiles(Directory(p.join(packageRoot, 'evals'))),
      ]..sort((a, b) => a.path.compareTo(b.path));

      expect(
        evalsFiles,
        isNotEmpty,
        reason: 'Should find at least one evals.json file in skills or .agents/skills.',
      );

      _verifyStructuralConsistency(evalsFiles, 'evals', optionalItemKeys: optionalItemKeys);
    });

    // Note: We intentionally only require an evals.json file for published skills.
    // Contributor skills in .agents/skills/ are not required to have one.
    test('all published skills have an evals.json file', () async {
      final Uri? packageUri = await Isolate.resolvePackageUri(Uri.parse('package:skills_lint/'));
      final String packageRoot = packageUri!.resolve('..').toFilePath();

      final skillsDir = Directory(p.join(packageRoot, 'skills'));
      if (!skillsDir.existsSync()) {
        return;
      }

      final List<Directory> skillDirs = skillsDir.listSync().whereType<Directory>().toList();

      for (final skillDir in skillDirs) {
        final evalsFile = File(p.join(skillDir.path, 'evals', 'evals.json'));
        expect(
          evalsFile.existsSync(),
          isTrue,
          reason:
              'Published skill "${p.basename(skillDir.path)}" is missing an evals.json file at ${evalsFile.path}',
        );
      }
    });

    test('all rubric JSON files in evals/ share consistent structure and keys', () async {
      final Uri? packageUri = await Isolate.resolvePackageUri(Uri.parse('package:skills_lint/'));
      final String packageRoot = packageUri!.resolve('..').toFilePath();

      final rubricsDir = Directory(p.join(packageRoot, 'evals'));
      if (!rubricsDir.existsSync()) {
        return;
      }

      final List<File> rubricFiles =
          rubricsDir
              .listSync()
              .whereType<File>()
              .where((File f) => f.path.endsWith('.json') && !f.path.endsWith('_evals.json'))
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));

      if (rubricFiles.isEmpty) {
        return;
      }

      _verifyStructuralConsistency(rubricFiles, 'evals');
    });

    test('all test_data references point to files or directories that exist', () async {
      final Uri? packageUri = await Isolate.resolvePackageUri(Uri.parse('package:skills_lint/'));
      final String packageRoot = packageUri!.resolve('..').toFilePath();

      final List<File> evalsFiles = [
        ..._findEvalsFiles(Directory(p.join(packageRoot, 'skills'))),
        ..._findEvalsFiles(
          Directory(p.normalize(p.join(packageRoot, '..', '..', '.agents', 'skills'))),
        ),
        ..._findEvalsFiles(Directory(p.join(packageRoot, 'evals'))),
      ];

      for (final file in evalsFiles) {
        final decoded = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        final items = decoded['evals'] as List<dynamic>;
        for (final item in items) {
          final itemMap = item as Map<String, dynamic>;
          final Object? testData = itemMap['test_data'];
          if (testData is String) {
            final String targetPath = p.normalize(p.join(packageRoot, testData));
            expect(
              FileSystemEntity.typeSync(targetPath) != FileSystemEntityType.notFound,
              isTrue,
              reason:
                  'File ${file.path} references test_data "$testData" which does not exist at $targetPath',
            );
          } else if (testData is List) {
            for (final String path in testData.whereType<String>()) {
              final String targetPath = p.normalize(p.join(packageRoot, path));
              expect(
                FileSystemEntity.typeSync(targetPath) != FileSystemEntityType.notFound,
                isTrue,
                reason:
                    'File ${file.path} references test_data "$path" which does not exist at $targetPath',
              );
            }
          }
        }
      }
    });
  });
}

void _verifyStructuralConsistency(
  List<File> files,
  String itemsKey, {
  Set<String> optionalItemKeys = const {},
}) {
  Set<String>? expectedRootKeys;
  String? expectedRootKeysFilePath;
  Set<String>? expectedRequiredItemKeys;
  String? expectedItemFilePath;

  for (final file in files) {
    final Object? decoded = jsonDecode(file.readAsStringSync());
    final Map<String, dynamic> decodedMap = switch (decoded) {
      final Map<String, dynamic> map => map,
      _ => fail('${file.path} must be a JSON map.'),
    };
    final Set<String> rootKeys = decodedMap.keys.toSet();
    if (expectedRootKeys == null) {
      expectedRootKeys = rootKeys;
      expectedRootKeysFilePath = file.path;
    } else {
      expect(
        rootKeys,
        equals(expectedRootKeys),
        reason:
            '${file.path} root keys do not match consistency pattern. '
            'Expected keys to match the first processed file ($expectedRootKeysFilePath).',
      );
    }

    final Object? itemsRaw = decodedMap[itemsKey];
    final List<dynamic> itemsList = switch (itemsRaw) {
      final List<dynamic> list => list,
      _ => fail('$itemsKey key in ${file.path} must be a List.'),
    };
    for (final Object? item in itemsList) {
      final Map<String, dynamic> itemMap = switch (item) {
        final Map<String, dynamic> map => map,
        _ => fail('Item in $itemsKey list in ${file.path} must be a JSON map.'),
      };
      final Set<String> itemKeys = itemMap.keys.toSet();
      final Set<String> requiredItemKeys = itemKeys.difference(optionalItemKeys);
      if (expectedRequiredItemKeys == null) {
        expectedRequiredItemKeys = requiredItemKeys;
        expectedItemFilePath = file.path;
      } else {
        expect(
          requiredItemKeys,
          equals(expectedRequiredItemKeys),
          reason:
              'Item in ${file.path} keys do not match consistency pattern. '
              'Expected required item keys to match the first processed file ($expectedItemFilePath).',
        );
      }

      final Set<String> extraKeys = itemKeys.difference(expectedRequiredItemKeys);
      expect(
        extraKeys.difference(optionalItemKeys),
        isEmpty,
        reason:
            'Item in ${file.path} contains unrecognized keys: '
            '${extraKeys.difference(optionalItemKeys)}',
      );
    }
  }
}

List<File> _findEvalsFiles(Directory baseDir) {
  if (!baseDir.existsSync()) {
    return [];
  }
  return baseDir.listSync(recursive: true).whereType<File>().where((File f) {
    final String name = p.basename(f.path);
    return name == 'evals.json' || name.endsWith('_evals.json');
  }).toList();
}
