// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('Triggers structure consistency', () {
    test('all triggers.json files across skills share consistent structure and keys', () async {
      final List<File> triggerFiles = await _getTriggerFiles();

      expect(
        triggerFiles,
        isNotEmpty,
        reason: 'Should find at least one triggers.json file in skills or .agents/skills.',
      );

      _verifyTriggersKeyConsistency(triggerFiles);
    });

    test('all published skills have a triggers.json file', () async {
      final String packageRoot = await _resolvePackageRoot();
      final skillsDir = Directory(p.join(packageRoot, 'skills'));
      if (!skillsDir.existsSync()) {
        return;
      }

      final List<Directory> skillDirs = skillsDir.listSync().whereType<Directory>().toList();

      for (final skillDir in skillDirs) {
        final triggersFile = File(p.join(skillDir.path, 'evals', 'triggers.json'));
        expect(
          triggersFile.existsSync(),
          isTrue,
          reason:
              'Published skill "${p.basename(skillDir.path)}" is missing a triggers.json file at ${triggersFile.path}',
        );
      }
    });

    test('triggers.json contents adhere to schema constraints', () async {
      final List<File> triggerFiles = await _getTriggerFiles();

      triggerFiles.forEach(_validateTriggerFile);
    });
  });
}

Future<String> _resolvePackageRoot() async {
  final Uri? packageUri = await Isolate.resolvePackageUri(Uri.parse('package:skills_lint/'));
  return packageUri!.resolve('..').toFilePath();
}

Future<List<File>> _getTriggerFiles() async {
  final String packageRoot = await _resolvePackageRoot();
  return [
    ..._findTriggerFiles(Directory(p.join(packageRoot, 'skills'))),
    ..._findTriggerFiles(Directory(p.join(packageRoot, '.agents', 'skills'))),
  ]..sort((a, b) => a.path.compareTo(b.path));
}

void _verifyTriggersKeyConsistency(List<File> triggerFiles) {
  Set<String>? expectedRootKeys;
  String? expectedRootKeysFilePath;

  for (final file in triggerFiles) {
    final Map<String, dynamic> decodedMap = _decodeJsonMap(file);
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
            'Expected keys to match $expectedRootKeysFilePath.',
      );
    }
  }
}

void _validateTriggerFile(File file) {
  final Map<String, dynamic> decodedMap = _decodeJsonMap(file);

  // 1. Check skill name matches parent skill directory
  final skillName = decodedMap['skill'] as String;
  final String parentDirName = p.basename(p.dirname(p.dirname(file.path)));
  expect(
    skillName,
    equals(parentDirName),
    reason:
        'Skill name in ${file.path} ("$skillName") must match directory name ("$parentDirName").',
  );

  // 2. Check positive_triggers is non-empty list of unique non-empty strings
  final Set<String> positiveSeen = _validatePositiveTriggers(file, decodedMap['positive_triggers']);

  // 3. Check distractors is a list of unique non-empty strings non-overlapping with positive_triggers
  _validateDistractors(file, decodedMap['distractors'], positiveSeen);
}

Set<String> _validatePositiveTriggers(File file, Object? raw) {
  expect(raw, isA<List<dynamic>>(), reason: 'positive_triggers in ${file.path} must be a List.');
  final list = raw! as List<dynamic>;
  expect(list, isNotEmpty, reason: 'positive_triggers in ${file.path} must not be empty.');

  final seen = <String>{};
  for (final item in list) {
    expect(
      item,
      isA<String>(),
      reason: 'Item in positive_triggers in ${file.path} must be a String.',
    );
    final String str = (item as String).trim();
    expect(
      str,
      isNotEmpty,
      reason: 'Trigger prompt in ${file.path} cannot be empty or whitespace.',
    );
    expect(
      seen.add(str),
      isTrue,
      reason: 'Duplicate positive trigger prompt found in ${file.path}: "$str"',
    );
  }
  return seen;
}

void _validateDistractors(File file, Object? raw, Set<String> positiveSeen) {
  expect(raw, isA<List<dynamic>>(), reason: 'distractors in ${file.path} must be a List.');
  final list = raw! as List<dynamic>;

  final seen = <String>{};
  for (final item in list) {
    expect(item, isA<String>(), reason: 'Item in distractors in ${file.path} must be a String.');
    final String str = (item as String).trim();
    expect(
      str,
      isNotEmpty,
      reason: 'Distractor prompt in ${file.path} cannot be empty or whitespace.',
    );
    expect(
      seen.add(str),
      isTrue,
      reason: 'Duplicate distractor prompt found in ${file.path}: "$str"',
    );
    expect(
      positiveSeen.contains(str),
      isFalse,
      reason: 'Distractor prompt in ${file.path} cannot also be in positive_triggers: "$str"',
    );
  }
}

Map<String, dynamic> _decodeJsonMap(File file) {
  final Object? decoded = jsonDecode(file.readAsStringSync());
  return switch (decoded) {
    final Map<String, dynamic> map => map,
    _ => fail('${file.path} must be a JSON map.'),
  };
}

List<File> _findTriggerFiles(Directory baseDir) {
  if (!baseDir.existsSync()) {
    return [];
  }
  return baseDir.listSync(recursive: true).whereType<File>().where((File f) {
    return p.basename(f.path) == 'triggers.json';
  }).toList();
}
