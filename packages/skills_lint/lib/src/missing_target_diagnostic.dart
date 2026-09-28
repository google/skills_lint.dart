// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;

import 'models/source_region.dart';
import 'models/target_declaration.dart';
import 'suggestions/missing_directory_suggestion.dart';

/// The kind of target a missing-target diagnostic describes.
enum MissingTargetKind {
  /// A directory of skills, from `-d` or `directories`.
  skillsRoot('root directory'),

  /// A single skill directory, from `--skill` or `individual_skills`.
  skill('skill directory');

  const MissingTargetKind(this.label);

  /// How the diagnostic names this kind of target.
  final String label;
}

/// A diagnostic for a target that does not exist.
///
/// [text] is the plain-text message, [markdown] the rich form for SARIF and
/// JSON (or `null` when [text] says everything), and [file] and [region] the
/// location to report.
typedef MissingTargetDiagnostic = ({
  String text,
  String? markdown,
  String file,
  SourceRegion? region,
});

/// Describes a [kind] of target at [resolvedPath] that does not exist.
///
/// The first line of the text always names [resolvedPath]. What follows
/// depends on where the target came from:
///
/// - [declaration]: a configuration target. The second line shows the path as
///   declared, the file and line that declared it, the directory it resolved
///   against, and a suggestion when one is found. The location is the
///   declaring line of the configuration file when that file is known.
/// - [cliText]: a command-line target, as typed. A second line appears only
///   when there is a suggestion.
/// - Neither: the first line alone.
///
/// [workingDirectory] is the directory the tool runs in.
MissingTargetDiagnostic missingTargetDiagnostic({
  required MissingTargetKind kind,
  required String resolvedPath,
  required String workingDirectory,
  TargetDeclaration? declaration,
  String? cliText,
}) {
  final headline = 'Specified ${kind.label} does not exist: $resolvedPath';
  if (declaration != null) {
    return _configurationDiagnostic(
      kind: kind,
      headline: headline,
      resolvedPath: resolvedPath,
      workingDirectory: workingDirectory,
      declaration: declaration,
    );
  }
  if (cliText != null) {
    return _commandLineDiagnostic(
      kind: kind,
      headline: headline,
      resolvedPath: resolvedPath,
      workingDirectory: workingDirectory,
      cliText: cliText,
    );
  }
  return (text: headline, markdown: null, file: resolvedPath, region: null);
}

MissingTargetDiagnostic _configurationDiagnostic({
  required MissingTargetKind kind,
  required String headline,
  required String resolvedPath,
  required String workingDirectory,
  required TargetDeclaration declaration,
}) {
  final String declared = declaration.declaredPath;
  final String anchor = declaration.anchorDirectory;
  final String? file = declaration.file;
  final int? line = declaration.line;
  final String? suggestion = suggestDirectory(
    declaredText: declared,
    resolvedPath: resolvedPath,
    baseDirectory: anchor,
    workingDirectory: workingDirectory,
  );

  final String where = switch ((file, line)) {
    (null, _) => 'configuration',
    (final String f, null) => f,
    (final String f, final int l) => '$f:$l',
  };
  final didYouMean = suggestion == null ? '' : ' Did you mean "$suggestion"?';

  final anchorGuidance = file != null && p.equals(p.dirname(file), anchor)
      ? 'Paths in a configuration file are relative to the directory containing '
            'that file (`$anchor${p.separator}`).'
      : 'Paths in this configuration are relative to `$anchor${p.separator}`.';

  return (
    text: '$headline\n  Declared as "$declared" in $where, relative to $anchor.$didYouMean',
    markdown: _markdown(kind, declared, suggestion, anchorGuidance: anchorGuidance),
    file: file ?? resolvedPath,
    region: file != null && line != null ? SourceRegion(startLine: line) : null,
  );
}

MissingTargetDiagnostic _commandLineDiagnostic({
  required MissingTargetKind kind,
  required String headline,
  required String resolvedPath,
  required String workingDirectory,
  required String cliText,
}) {
  final String? suggestion = suggestDirectory(
    declaredText: cliText,
    resolvedPath: resolvedPath,
    baseDirectory: workingDirectory,
  );
  if (suggestion == null) {
    return (text: headline, markdown: null, file: resolvedPath, region: null);
  }
  return (
    text: '$headline\n  Did you mean "$suggestion"?',
    markdown: _markdown(kind, cliText, suggestion),
    file: resolvedPath,
    region: null,
  );
}

/// Builds the markdown form, laid out like the `check-relative-paths`
/// diagnostic.
String _markdown(
  MissingTargetKind kind,
  String declared,
  String? suggestion, {
  String? anchorGuidance,
}) {
  return <String>[
    '**Specified ${kind.label} does not exist:** `$declared`',
    '',
    '**How to fix:**',
    '- Check for typos in `$declared`.',
    if (anchorGuidance != null) '- $anchorGuidance',
    if (suggestion != null) ...<String>['', '*Did you mean `$suggestion`?*'],
  ].join('\n');
}
