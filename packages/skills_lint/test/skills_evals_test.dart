// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Optional root keys permitted across `evals.json` and rubric files.
const Set<String> optionalRootKeys = {'repo_criteria', 'test_data', 'type'};

/// Optional item keys permitted across all `evals.json` and rubric files.
/// Maintainers can add optional keys to this set.
const Set<String> optionalItemKeys = {'test_data'};

void main() {
  group('Evals structure consistency', () {
    test(
      'all evals.json files across skills share consistent structure and keys',
      _testAllEvalsShareConsistentStructure,
    );

    test('all published skills have an evals.json file', _testPublishedSkillsHaveEvals);

    test(
      'all rubric JSON files in evals/ share consistent structure and keys',
      _testRubricsShareConsistentStructure,
    );

    test(
      'all repo_criteria references point to rubric files that exist',
      _testRepoCriteriaReferencesExist,
    );

    test(
      'all test_data references point to files or directories that exist',
      _testTestDataReferencesExist,
    );

    test(
      'when test_data is present as a root key in evals.json it is a boolean',
      _testRootTestDataIsBoolean,
    );

    test(
      'when type is present as a root key it is a valid evaluation mode',
      _testTypeKeyValidValues,
    );
  });
}

Future<String> _resolvePackageRoot() async {
  final Uri? packageUri = await Isolate.resolvePackageUri(Uri.parse('package:skills_lint/'));
  return packageUri!.resolve('..').toFilePath();
}

Future<List<File>> _getAllEvalsFiles() async {
  final String packageRoot = await _resolvePackageRoot();
  return [
    ..._findEvalsFiles(Directory(p.join(packageRoot, 'skills'))),
    ..._findEvalsFiles(
      Directory(p.normalize(p.join(packageRoot, '..', '..', '.agents', 'skills'))),
    ),
    ..._findEvalsFiles(Directory(p.join(packageRoot, 'evals'))),
  ]..sort((a, b) => a.path.compareTo(b.path));
}

Future<void> _testAllEvalsShareConsistentStructure() async {
  final List<File> evalsFiles = await _getAllEvalsFiles();
  expect(
    evalsFiles,
    isNotEmpty,
    reason: 'Should find at least one evals.json file in skills or .agents/skills.',
  );

  _verifyStructuralConsistency(
    evalsFiles,
    'evals',
    optionalRootKeys: optionalRootKeys,
    optionalItemKeys: optionalItemKeys,
  );
}

Future<void> _testPublishedSkillsHaveEvals() async {
  final String packageRoot = await _resolvePackageRoot();
  final skillsDir = Directory(p.join(packageRoot, 'skills'));
  expect(
    skillsDir.existsSync(),
    isTrue,
    reason: 'Published skills directory should exist at ${skillsDir.path}',
  );

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
}

Future<void> _testRubricsShareConsistentStructure() async {
  final String packageRoot = await _resolvePackageRoot();
  final rubricsDir = Directory(p.join(packageRoot, 'evals'));
  expect(
    rubricsDir.existsSync(),
    isTrue,
    reason: 'Rubrics directory should exist at ${rubricsDir.path}',
  );

  final List<File> rubricFiles =
      rubricsDir
          .listSync()
          .whereType<File>()
          .where((File f) => f.path.endsWith('.json') && !f.path.endsWith('_evals.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  if (rubricFiles.isNotEmpty) {
    _verifyStructuralConsistency(rubricFiles, 'evals');
  }
}

Future<void> _testRepoCriteriaReferencesExist() async {
  final String packageRoot = await _resolvePackageRoot();
  final String repoRoot = p.normalize(p.join(packageRoot, '..', '..'));
  final List<File> evalsFiles = await _getAllEvalsFiles();

  for (final file in evalsFiles) {
    final decoded = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    if (!decoded.containsKey('repo_criteria')) {
      continue;
    }
    final Object? criteria = decoded['repo_criteria'];
    expect(
      criteria,
      isA<List<dynamic>>(),
      reason: 'repo_criteria in ${file.path} must be a List of strings.',
    );
    final criteriaList = criteria! as List<dynamic>;
    for (final item in criteriaList) {
      expect(
        item,
        isA<String>(),
        reason: 'Each entry in repo_criteria in ${file.path} must be a String.',
      );
      final itemStr = item! as String;
      final String targetInPackage = p.normalize(p.join(packageRoot, itemStr));
      final String targetInRepo = p.normalize(p.join(repoRoot, itemStr));
      final bool exists = File(targetInPackage).existsSync() || File(targetInRepo).existsSync();
      expect(
        exists,
        isTrue,
        reason:
            'File ${file.path} references repo_criteria "$itemStr" which does not exist at $targetInPackage or $targetInRepo',
      );
    }
  }
}

Future<void> _testTestDataReferencesExist() async {
  final String packageRoot = await _resolvePackageRoot();
  final List<File> evalsFiles = await _getAllEvalsFiles();

  for (final file in evalsFiles) {
    final decoded = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final items = decoded['evals'] as List<dynamic>;
    for (var i = 0; i < items.length; i++) {
      final itemMap = items[i] as Map<String, dynamic>;
      if (!itemMap.containsKey('test_data')) {
        continue;
      }
      final Object? testData = itemMap['test_data'];
      expect(
        testData,
        anyOf(isA<String>(), isA<List<dynamic>>()),
        reason:
            'Item #$i in ${file.path} contains test_data of type ${testData.runtimeType}. '
            'Item-level test_data must be a String path or List of String paths, not a boolean.',
      );
      _verifyTestDataTarget(packageRoot, file.path, testData);
    }
  }
}

void _verifyTestDataTarget(String packageRoot, String filePath, Object? testData) {
  final String repoRoot = p.normalize(p.join(packageRoot, '..', '..'));
  if (testData is String) {
    final String targetInPackage = p.normalize(p.join(packageRoot, testData));
    final String targetInRepo = p.normalize(p.join(repoRoot, testData));
    final bool exists =
        FileSystemEntity.typeSync(targetInPackage) != FileSystemEntityType.notFound ||
        FileSystemEntity.typeSync(targetInRepo) != FileSystemEntityType.notFound;
    expect(
      exists,
      isTrue,
      reason:
          'File $filePath references test_data "$testData" which does not exist at $targetInPackage or $targetInRepo',
    );
  } else if (testData is List) {
    for (final Object? path in testData) {
      expect(path, isA<String>(), reason: 'test_data list entries in $filePath must be Strings.');
      final pathStr = path! as String;
      final String targetInPackage = p.normalize(p.join(packageRoot, pathStr));
      final String targetInRepo = p.normalize(p.join(repoRoot, pathStr));
      final bool exists =
          FileSystemEntity.typeSync(targetInPackage) != FileSystemEntityType.notFound ||
          FileSystemEntity.typeSync(targetInRepo) != FileSystemEntityType.notFound;
      expect(
        exists,
        isTrue,
        reason:
            'File $filePath references test_data "$pathStr" which does not exist at $targetInPackage or $targetInRepo',
      );
    }
  }
}

Future<void> _testRootTestDataIsBoolean() async {
  final List<File> evalsFiles = await _getAllEvalsFiles();
  for (final file in evalsFiles) {
    final decoded = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    if (decoded.containsKey('test_data')) {
      expect(
        decoded['test_data'],
        isA<bool>(),
        reason: 'Root test_data in ${file.path} must be a boolean.',
      );
    }
  }
}

Future<void> _testTypeKeyValidValues() async {
  final List<File> allFiles = [
    ...await _getAllEvalsFiles(),
    ...Directory(
      p.join(await _resolvePackageRoot(), 'evals'),
    ).listSync().whereType<File>().where((File f) => f.path.endsWith('.json')),
  ];
  for (final file in allFiles) {
    final decoded = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    if (decoded.containsKey('type')) {
      expect(
        decoded['type'],
        isIn(['audit', 'content']),
        reason:
            'Root "type" in ${file.path} must be one of: "audit", "content" '
            '(found: ${decoded['type']}).',
      );
    }
  }
}

void _verifyStructuralConsistency(
  List<File> files,
  String itemsKey, {
  Set<String> optionalRootKeys = const {},
  Set<String> optionalItemKeys = const {},
}) {
  Set<String>? expectedRequiredRootKeys;
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
    final Set<String> requiredRootKeys = rootKeys.difference(optionalRootKeys);
    if (expectedRequiredRootKeys == null) {
      expectedRequiredRootKeys = requiredRootKeys;
      expectedRootKeysFilePath = file.path;
    } else {
      expect(
        requiredRootKeys,
        equals(expectedRequiredRootKeys),
        reason:
            '${file.path} root keys do not match consistency pattern.\n'
            'Expected keys to match: $expectedRootKeysFilePath\n'
            'Missing required keys: ${expectedRequiredRootKeys.difference(requiredRootKeys)}\n'
            'Unexpected extra keys: ${requiredRootKeys.difference(expectedRequiredRootKeys)}',
      );
    }

    final Object? itemsRaw = decodedMap[itemsKey];
    final List<dynamic> itemsList = switch (itemsRaw) {
      final List<dynamic> list => list,
      _ => fail('$itemsKey key in ${file.path} must be a List (found ${itemsRaw.runtimeType}).'),
    };
    for (var i = 0; i < itemsList.length; i++) {
      final Object? item = itemsList[i];
      final Map<String, dynamic> itemMap = switch (item) {
        final Map<String, dynamic> map => map,
        _ => fail('Item #$i in $itemsKey list in ${file.path} must be a JSON map.'),
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
              'Item #${itemMap['id'] ?? i} in ${file.path} keys do not match consistency pattern.\n'
              'Expected required item keys to match: $expectedItemFilePath\n'
              'Missing required keys: ${expectedRequiredItemKeys.difference(requiredItemKeys)}\n'
              'Unexpected extra keys: ${requiredItemKeys.difference(expectedRequiredItemKeys)}',
        );
      }
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
