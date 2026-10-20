// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Detectors for GitHub Actions workflows and composite actions that pin one
/// action, reusable workflow or Docker image in more than one way.
///
/// Every use of an action should name the same ref and version comment.
/// Dependabot (`.github/dependabot.yaml`) updates every use in one pull
/// request, but a hand edit can change one workflow and miss the others. Some
/// workflows then run an older version than the rest, or a version comment
/// names a release that its commit isn't.
///
/// Change this rule if a workflow needs a different version of an action on
/// purpose, for example to test against an older release.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'models/convention_violation.dart';

/// One `uses:` reference to an action, reusable workflow or Docker image
/// outside this repository.
final class ActionPin {
  ActionPin(this.path, this.line, this.name, this.ref, this.comment);

  /// Repository-relative path of the workflow or action file, with `/`
  /// separators.
  final String path;

  /// 1-based line of the `uses:` value.
  final int line;

  /// The `uses:` value up to its ref: `owner/repo` or `owner/repo/path` for
  /// actions and reusable workflows, `docker://image` for Docker images.
  final String name;

  /// The rest of the `uses:` value after [name], starting with `@` (or `:`
  /// for a Docker tag). Empty if the value has no ref.
  final String ref;

  /// The first word of the comment on the same line, such as `v7.0.1`, or
  /// null if the line has no comment.
  final String? comment;

  /// The ref and version comment, as written after [name].
  String get pin => comment == null ? ref : '$ref # $comment';
}

/// The workflow and action files under [repoRoot] whose pins must agree.
///
/// These are every `.yaml` workflow in `.github/workflows/` and the
/// `action.yaml` of every composite action that a workflow or another
/// scanned action names in a local `uses: ./<path>`, wherever that action
/// lives. The result is sorted by path. A local `uses:` that names a file,
/// such as a reusable workflow, adds nothing: the workflow scan covers the
/// workflows.
///
/// Throws a [StateError] if `.github/workflows/` is missing, so a moved
/// directory fails the scan instead of leaving its files unchecked. Also
/// throws if a workflow or a referenced action uses the `.yml` extension,
/// which GitHub accepts too, so that no workflow or action goes unchecked.
/// Also throws on a `.github/dependabot.yml`: Dependabot reads it in
/// preference to `.github/dependabot.yaml`, so a stray copy would replace the
/// configuration that groups action updates. Also throws if a local `uses:`
/// names a directory with no action file, giving the file, line and path.
List<File> actionPinFiles(String repoRoot) {
  final workflows = Directory(p.join(repoRoot, '.github', 'workflows'));
  if (!workflows.existsSync()) {
    throw StateError('${workflows.path} does not exist, so its action pins are not checked.');
  }
  final List<File> workflowFiles = [
    for (final entry in workflows.listSync())
      if (entry is File) entry,
  ];
  final dependabot = File(p.join(repoRoot, '.github', 'dependabot.yml'));
  final List<String> ymlFiles = [
    for (final File(:path) in workflowFiles)
      if (p.extension(path) == '.yml') path,
    if (dependabot.existsSync()) dependabot.path,
  ];
  _throwIfYml(ymlFiles);
  final Map<String, File> found = {
    for (final File file in workflowFiles)
      if (p.extension(file.path) == '.yaml') p.normalize(file.path): file,
  };
  final List<File> pending = [...found.values];
  final List<String> missing = [];
  while (pending.isNotEmpty) {
    final File file = pending.removeLast();
    for (final _LocalAction action in _localActions(repoRoot, file)) {
      final yaml = File(p.join(action.directory, 'action.yaml'));
      final yml = File(p.join(action.directory, 'action.yml'));
      if (yml.existsSync()) {
        ymlFiles.add(yml.path);
      } else if (!yaml.existsSync()) {
        missing.add(
          '${action.source}:${action.line}: `uses: ${action.value}` names no '
          'action.yaml in ${action.directory}',
        );
      } else if (!found.containsKey(p.normalize(yaml.path))) {
        found[p.normalize(yaml.path)] = yaml;
        pending.add(yaml);
      }
    }
  }
  _throwIfYml(ymlFiles);
  if (missing.isNotEmpty) {
    throw StateError('These local actions have no action file: ${missing.join('; ')}');
  }
  return found.values.toList()..sort((a, b) => a.path.compareTo(b.path));
}

/// Throws a [StateError] naming [ymlFiles] unless it is empty.
void _throwIfYml(List<String> ymlFiles) {
  if (ymlFiles.isNotEmpty) {
    throw StateError(
      'Rename these files to end in .yaml, as the others do: ${ymlFiles.join(', ')}',
    );
  }
}

/// A local `uses: ./<path>` that names a directory, which GitHub runs as a
/// composite action.
final class _LocalAction {
  _LocalAction(this.source, this.line, this.value, this.directory);

  /// Path of the workflow or action file that holds the `uses:`.
  final String source;

  /// 1-based line of the `uses:` value.
  final int line;

  /// The `uses:` value as written.
  final String value;

  /// The directory the value names, joined to the repository root.
  final String directory;
}

/// The local `uses:` values in [file] that name a directory or nothing at
/// all, resolved against [repoRoot].
///
/// Values that name a file, such as a reusable workflow, are left out.
Iterable<_LocalAction> _localActions(String repoRoot, File file) sync* {
  for (final YamlScalar node in _usesNodes(loadYamlNode(file.readAsStringSync()))) {
    if (node.value case final String value when value.startsWith('./')) {
      final String target = p.normalize(p.joinAll([repoRoot, ...value.split('/')]));
      if (!File(target).existsSync()) {
        yield _LocalAction(file.path, node.span.start.line + 1, value, target);
      }
    }
  }
}

/// Finds the `uses:` references in a workflow or composite action.
///
/// Reads a workflow's `jobs.<id>.uses` and `jobs.<id>.steps[*].uses`, or a
/// composite action's `runs.steps[*].uses`, from [content], in file order.
///
/// The [path] is the file's repository-relative path, used in each
/// [ActionPin]. Local references (`./...`) are skipped: they name code in
/// this repository at the same commit, so they have no pin.
List<ActionPin> findActionPins(String path, String content) => [
  for (final YamlScalar node in _usesNodes(loadYamlNode(content)))
    if (node.value case final String value when !value.startsWith('./'))
      _parsePin(path, content, node, value),
];

/// Reports every use in [pins] whose [ActionPin.pin] differs from another use
/// of the same [ActionPin.name], sorted by path and line.
List<ConventionViolation> findInconsistentPins(Iterable<ActionPin> pins) {
  final Map<String, List<ActionPin>> byName = {};
  for (final pin in pins) {
    (byName[pin.name] ??= []).add(pin);
  }
  return [
    for (final List<ActionPin> uses in byName.values)
      for (final ActionPin use in uses)
        if (uses.any((other) => other.pin != use.pin))
          ConventionViolation(use.path, use.line, _inconsistentPinProblem(use, uses)),
  ]..sort((a, b) => a.path == b.path ? a.line.compareTo(b.line) : a.path.compareTo(b.path));
}

/// The `uses:` scalars of every job and step in a workflow document, and of
/// every step in a composite action's `runs`.
Iterable<YamlScalar> _usesNodes(YamlNode root) sync* {
  if (root is! YamlMap) {
    return;
  }
  // Each `yield*` costs more than a plain loop, so skip it when there are no
  // steps to visit.
  if (root.nodes['runs'] case YamlMap(
    nodes: {'steps': final YamlList steps},
  ) when steps.isNotEmpty) {
    yield* _stepUses(steps);
  }
  if (root.nodes['jobs'] case YamlMap(nodes: final jobs)) {
    for (final YamlMap(nodes: job) in jobs.values.whereType<YamlMap>()) {
      if (job['uses'] case final YamlScalar uses) {
        yield uses;
      }
      if (job['steps'] case final YamlList steps when steps.isNotEmpty) {
        yield* _stepUses(steps);
      }
    }
  }
}

/// The `uses:` scalars of the steps in [steps].
Iterable<YamlScalar> _stepUses(YamlList steps) sync* {
  for (final YamlMap(nodes: step) in steps.nodes.whereType<YamlMap>()) {
    if (step['uses'] case final YamlScalar uses) {
      yield uses;
    }
  }
}

/// Matches the start of a YAML comment after a value and captures its first
/// word.
final RegExp _versionComment = RegExp(r'[ \t]+#[ \t]*([^\s#]+)');

ActionPin _parsePin(String path, String content, YamlScalar node, String value) {
  final (String name, String ref) = _splitRef(value);
  final String? comment = _versionComment.matchAsPrefix(content, node.span.end.offset)?[1];
  return ActionPin(path, node.span.start.line + 1, name, ref, comment);
}

/// Splits a `uses:` value into its name and ref, as described on
/// [ActionPin.name] and [ActionPin.ref].
(String, String) _splitRef(String value) {
  const dockerScheme = 'docker://';
  if (!value.startsWith(dockerScheme)) {
    final int at = value.indexOf('@');
    return at < 0 ? (value, '') : (value.substring(0, at), value.substring(at));
  }
  final String image = value.substring(dockerScheme.length);
  final int digest = image.indexOf('@');
  final int tag = image.lastIndexOf(':');
  final int end = digest >= 0
      ? digest
      : tag > image.lastIndexOf('/')
      ? tag
      : image.length;
  return ('$dockerScheme${image.substring(0, end)}', image.substring(end));
}

String _inconsistentPinProblem(ActionPin use, List<ActionPin> uses) {
  final Set<String> others = {
    for (final ActionPin other in uses)
      if (other.pin != use.pin) '`${other.pin}`',
  };
  return '`${use.name}${use.pin}`, but other uses pin ${others.join(', ')}';
}
