// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Detectors for GitHub Actions workflows and composite actions that pin one
/// action, reusable workflow or Docker image in more than one way.
///
/// Every use of an action should name the same ref and version comment.
/// Dependabot (`.github/dependabot.yml`) updates every use in one pull
/// request, but a hand edit can change one workflow and miss the others. Some
/// workflows then run an older version than the rest, or a version comment
/// names a release that its commit isn't.
///
/// Change this rule if a workflow needs a different version of an action on
/// purpose, for example to test against an older release.
library;

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

/// Returns the `uses:` references in [content], in file order: a workflow's
/// `jobs.<id>.uses` and `jobs.<id>.steps[*].uses`, or a composite action's
/// `runs.steps[*].uses`.
///
/// [path] is the file's repository-relative path, used in each
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
  final YamlNode? runs = root.nodes['runs'];
  if (runs is YamlMap) {
    yield* _stepUses(runs.nodes['steps']);
  }
  final YamlNode? jobs = root.nodes['jobs'];
  if (jobs is! YamlMap) {
    return;
  }
  for (final YamlNode job in jobs.nodes.values) {
    if (job is! YamlMap) {
      continue;
    }
    if (job.nodes['uses'] case final YamlScalar uses) {
      yield uses;
    }
    yield* _stepUses(job.nodes['steps']);
  }
}

/// The `uses:` scalars of the steps in [steps], a YAML list of steps.
Iterable<YamlScalar> _stepUses(YamlNode? steps) sync* {
  if (steps is! YamlList) {
    return;
  }
  for (final YamlNode step in steps.nodes) {
    if (step is! YamlMap) {
      continue;
    }
    if (step.nodes['uses'] case final YamlScalar uses) {
      yield uses;
    }
  }
}

/// Matches the start of a YAML comment after a value and captures its first
/// word.
final RegExp _versionComment = RegExp(r'[ \t]+#[ \t]*([^\s#]+)');

ActionPin _parsePin(String path, String content, YamlScalar node, String value) {
  final (String name, String ref) = _splitRef(value);
  final String? comment = _versionComment.matchAsPrefix(content, node.span.end.offset)?.group(1);
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
