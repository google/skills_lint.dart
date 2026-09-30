// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Key of the prompt string in an object entry of `positive_triggers`.
const String keyPrompt = 'prompt';

/// Key of the skill-name list in an object entry of `positive_triggers`.
const String keyPermittedCoTriggers = 'permitted_co_triggers';

/// Result of [checkPositiveTriggers].
typedef PositiveTriggersCheck = ({Set<String> prompts, List<String> errors});

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
      final Set<String> knownSkills = await _getKnownSkillNames();

      for (final file in triggerFiles) {
        _validateTriggerFile(file, knownSkills);
      }
    });
  });

  group('positive_triggers entry checks', () {
    const String skill = 'target-skill';
    const Set<String> knownSkills = {'target-skill', 'peer-skill', 'other-skill'};

    List<String> errorsFor(Object? entries) {
      return checkPositiveTriggers(entries, skill: skill, knownSkills: knownSkills).errors;
    }

    test('accepts plain string entries', () {
      final PositiveTriggersCheck result = checkPositiveTriggers(
        ['Run the checks'],
        skill: skill,
        knownSkills: knownSkills,
      );

      expect(result.errors, isEmpty);
      expect(result.prompts, {'Run the checks'});
    });

    test('accepts an object entry with known permitted_co_triggers', () {
      final PositiveTriggersCheck result = checkPositiveTriggers(
        [
          'Run the checks',
          {
            keyPrompt: 'Author a rule',
            keyPermittedCoTriggers: ['peer-skill', 'other-skill'],
          },
        ],
        skill: skill,
        knownSkills: knownSkills,
      );

      expect(result.errors, isEmpty);
      expect(result.prompts, {'Run the checks', 'Author a rule'});
    });

    test('rejects an unknown skill in permitted_co_triggers', () {
      expect(
        errorsFor([
          {
            keyPrompt: 'Author a rule',
            keyPermittedCoTriggers: ['missing-skill'],
          },
        ]),
        [contains('unknown skill "missing-skill"')],
      );
    });

    test('rejects the target skill in permitted_co_triggers', () {
      expect(
        errorsFor([
          {
            keyPrompt: 'Author a rule',
            keyPermittedCoTriggers: [skill],
          },
        ]),
        [contains('must not list the target skill')],
      );
    });

    test('rejects duplicate skills in permitted_co_triggers', () {
      expect(
        errorsFor([
          {
            keyPrompt: 'Author a rule',
            keyPermittedCoTriggers: ['peer-skill', 'peer-skill'],
          },
        ]),
        [contains('duplicate skill "peer-skill"')],
      );
    });

    test('rejects an empty permitted_co_triggers list', () {
      expect(
        errorsFor([
          {keyPrompt: 'Author a rule', keyPermittedCoTriggers: <String>[]},
        ]),
        [contains('non-empty list')],
      );
    });

    test('rejects an object entry with missing or unexpected keys', () {
      expect(
        errorsFor([
          {keyPrompt: 'Author a rule', 'distractors': <String>[]},
        ]),
        [contains('must have exactly the keys')],
      );
    });

    test('rejects an object entry whose prompt is blank', () {
      expect(
        errorsFor([
          {
            keyPrompt: '  ',
            keyPermittedCoTriggers: ['peer-skill'],
          },
        ]),
        [contains('cannot be empty or whitespace')],
      );
    });

    test('rejects a duplicate prompt across string and object entries', () {
      expect(
        errorsFor([
          'Author a rule',
          {
            keyPrompt: 'Author a rule',
            keyPermittedCoTriggers: ['peer-skill'],
          },
        ]),
        [contains('Duplicate positive trigger prompt')],
      );
    });

    test('rejects entries that are neither a string nor an object', () {
      expect(errorsFor([42]), [contains('must be a String or an object')]);
    });

    test('rejects an empty or non-list positive_triggers value', () {
      expect(errorsFor(<Object?>[]), [contains('must not be empty')]);
      expect(errorsFor('x'), [contains('must be a List')]);
    });
  });
}

Future<String> _resolvePackageRoot() async {
  final Uri? packageUri = await Isolate.resolvePackageUri(Uri.parse('package:skills_lint/'));
  return packageUri!.resolve('..').toFilePath();
}

Future<List<Directory>> _getSkillRoots() async {
  final String packageRoot = await _resolvePackageRoot();
  return [
    Directory(p.join(packageRoot, 'skills')),
    Directory(p.normalize(p.join(packageRoot, '..', '..', '.agents', 'skills'))),
  ];
}

Future<List<File>> _getTriggerFiles() async {
  final List<Directory> roots = await _getSkillRoots();
  return [for (final root in roots) ..._findTriggerFiles(root)]
    ..sort((a, b) => a.path.compareTo(b.path));
}

/// Returns the names of skill directories that contain a `SKILL.md` in the
/// published and internal skill roots.
Future<Set<String>> _getKnownSkillNames() async {
  final List<Directory> roots = await _getSkillRoots();
  return {
    for (final root in roots.where((d) => d.existsSync()))
      for (final dir in root.listSync().whereType<Directory>())
        if (File(p.join(dir.path, 'SKILL.md')).existsSync()) p.basename(dir.path),
  };
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

void _validateTriggerFile(File file, Set<String> knownSkills) {
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

  // 2. Check positive_triggers is a non-empty list of unique non-empty prompts,
  // each given as a string or as an object with permitted_co_triggers.
  final PositiveTriggersCheck positive = checkPositiveTriggers(
    decodedMap['positive_triggers'],
    skill: skillName,
    knownSkills: knownSkills,
  );
  expect(positive.errors, isEmpty, reason: 'Invalid positive_triggers in ${file.path}.');

  // 3. Check distractors is a list of unique non-empty strings non-overlapping with positive_triggers
  _validateDistractors(file, decodedMap['distractors'], positive.prompts);
}

/// Checks a `positive_triggers` value from a `triggers.json` file.
///
/// Each entry is either a prompt string or an object with exactly the keys
/// [keyPrompt] and [keyPermittedCoTriggers]. Every name in
/// [keyPermittedCoTriggers] must be in [knownSkills] and must differ from
/// [skill].
///
/// Returns the trimmed prompts and one message per violation. `errors` is
/// empty when [raw] is valid.
PositiveTriggersCheck checkPositiveTriggers(
  Object? raw, {
  required String skill,
  required Set<String> knownSkills,
}) {
  final prompts = <String>{};
  final errors = <String>[];
  if (raw is! List<dynamic>) {
    return (prompts: prompts, errors: ['positive_triggers must be a List.']);
  }
  if (raw.isEmpty) {
    errors.add('positive_triggers must not be empty.');
  }
  for (final Object? item in raw) {
    final String? prompt = _entryPrompt(item, skill, knownSkills, errors);
    if (prompt == null) {
      continue;
    }
    if (prompt.isEmpty) {
      errors.add('Trigger prompt cannot be empty or whitespace.');
    } else if (!prompts.add(prompt)) {
      errors.add('Duplicate positive trigger prompt: "$prompt"');
    }
  }
  return (prompts: prompts, errors: errors);
}

/// Returns the trimmed prompt of a `positive_triggers` entry, or `null` when
/// the entry has no usable prompt. Adds violations to [errors].
String? _entryPrompt(Object? item, String skill, Set<String> knownSkills, List<String> errors) {
  switch (item) {
    case final String prompt:
      return prompt.trim();
    case final Map<String, dynamic> entry:
      return _objectEntryPrompt(entry, skill, knownSkills, errors);
    default:
      errors.add(
        'Item in positive_triggers must be a String or an object with '
        '"$keyPrompt" and "$keyPermittedCoTriggers": $item',
      );
      return null;
  }
}

String? _objectEntryPrompt(
  Map<String, dynamic> entry,
  String skill,
  Set<String> knownSkills,
  List<String> errors,
) {
  const Set<String> expectedKeys = {keyPrompt, keyPermittedCoTriggers};
  final Set<String> keys = entry.keys.toSet();
  if (keys.length != expectedKeys.length || !keys.containsAll(expectedKeys)) {
    errors.add(
      'Object entry in positive_triggers must have exactly the keys '
      '"$keyPrompt" and "$keyPermittedCoTriggers": $entry',
    );
    return null;
  }
  final Object? prompt = entry[keyPrompt];
  if (prompt is! String) {
    errors.add('"$keyPrompt" in positive_triggers must be a String: $entry');
    return null;
  }
  _checkCoTriggers(entry[keyPermittedCoTriggers], skill, knownSkills, errors);
  return prompt.trim();
}

void _checkCoTriggers(Object? raw, String skill, Set<String> knownSkills, List<String> errors) {
  if (raw is! List<dynamic> || raw.isEmpty) {
    errors.add('"$keyPermittedCoTriggers" must be a non-empty list of skill names.');
    return;
  }
  final seen = <String>{};
  for (final Object? name in raw) {
    if (name is! String) {
      errors.add('"$keyPermittedCoTriggers" entries must be Strings: $name');
    } else if (name == skill) {
      errors.add('"$keyPermittedCoTriggers" must not list the target skill "$skill".');
    } else if (!seen.add(name)) {
      errors.add('"$keyPermittedCoTriggers" has duplicate skill "$name".');
    } else if (!knownSkills.contains(name)) {
      errors.add('"$keyPermittedCoTriggers" names unknown skill "$name".');
    }
  }
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
