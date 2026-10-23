// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import 'config_parser.dart';
import 'missing_target_diagnostic.dart';
import 'models/analysis_severity.dart';
import 'models/check_type.dart';
import 'models/fix_outcome.dart';
import 'models/ignore_entry.dart';
import 'models/output_format.dart';
import 'models/pub_archive.dart';
import 'models/rule_config.dart';
import 'models/sarif/sarif.dart';
import 'models/skill_context.dart';
import 'models/skill_rule.dart';
import 'models/skills_ignores.dart';
import 'models/skipped_fix.dart';
import 'models/validation_error.dart';
import 'path_utils.dart';
import 'pub_archive_loader.dart';
import 'reporters/reporters.dart';
import 'rule_registry.dart';
import 'rules/pub_archive_includes_skill_rule.dart';
import 'skill_fixer.dart';
import 'skills_ignores_storage.dart';
import 'validator.dart';

final _log = Logger('skills_lint');

/// Default filename for the per-run ignore baseline file.
///
/// Referenced both by production code (the `--generate-baseline` help text in
/// the CLI) and by tests, so this is intentionally not `@visibleForTesting`.
const defaultIgnoreFileName = 'skills_lint_ignore.json';

/// Per-invocation state and orchestration for skill validation.
///
/// One session is constructed per CLI invocation (or embedded call). The
/// session aggregates configuration parameters, custom rules, ignores, and CLI overrides,
/// then orchestrates the validation of multiple target skill directories.
///
/// ## Path canonicalization contract
///
/// Pass paths in whatever form you have them. The session resolves each one as
/// it arrives, then compares absolute paths for the rest of the run, so a
/// result never depends on the directory the process started in.
///
/// Callers invoke [processIndividualSkill] for each `--skill` path and
/// [processSkillRoot] for each `--skills-directory` path, then optionally
/// [reportNoSkillsValidated] to emit the "no skills found" diagnostics.
/// The failure state of the session is exposed via [anyFailed] and [anySkillsValidated].
class ValidationSession {
  /// Creates a validation session with the specified configuration, overrides, and rules.
  ///
  /// * [config] is the parsed YAML configuration file settings.
  /// * [resolvedRuleConfigs] maps rule names to rule configuration patches (e.g., CLI-passed flags).
  /// * [ignoreFileOverride] specifies a custom file path containing lint ignores to load.
  /// * [customRules] contains programmatically injected custom skill rule checks.
  /// * [printWarnings] controls whether warnings are printed to stdout.
  /// * [fastFail] controls whether validation stops immediately on the first error.
  /// * [quiet] controls whether success messages and other info logs are silenced.
  /// * [generateBaseline] controls whether the validation should output/update baseline ignores.
  /// * [fix] controls whether to apply fixable rule modifications directly to files.
  /// * [fixApply] is the deprecated flag indicating if fixes should be automatically applied.
  // TODO(reidbaker): Remove deprecated fixApply parameter on next major version bump.
  /// * [format] specifies the output format for diagnostics ([OutputFormat.text], [OutputFormat.json], [OutputFormat.sarif]).
  /// * [pubArchiveLoader] lists the files pub publishes. Tests pass one with a
  ///   fake process runner.
  ValidationSession({
    required this.config,
    // TODO(reidbaker): https://github.com/google/skills_lint.dart/issues/75
    @Deprecated('Use resolvedRuleConfigs instead')
    Map<String, AnalysisSeverity> resolvedRules = const {},
    Map<String, RuleConfigPatch> resolvedRuleConfigs = const {},
    required String? ignoreFileOverride,
    required this.customRules,
    required this.printWarnings,
    required this.fastFail,
    required this.quiet,
    required this.generateBaseline,
    required this.fix,
    // TODO(reidbaker): Remove deprecated fixApply parameter on next major version bump.
    required this.fixApply,
    this.format = OutputFormat.text,
    @visibleForTesting PubArchiveLoader? pubArchiveLoader,
  }) : _pubArchiveLoader = pubArchiveLoader ?? PubArchiveLoader(),
       _reporter = Reporter.fromFormat(format, quiet: quiet, printWarnings: printWarnings),
       resolvedRuleConfigs = mergeDeprecatedRules(resolvedRules, resolvedRuleConfigs),
       ignoreFileOverride = _ingestOptionalPath(ignoreFileOverride),
       _normalizedDirectoryConfigs = [
         for (final dc in [...config.directoryConfigs, ...config.individualSkillConfigs])
           (
             normalizedPath: _ingestPath(dc.path),
             normalizedIgnoreFile: _ingestOptionalPath(dc.ignoreFile),
             config: dc,
           ),
       ];

  /// Anchors an externally supplied [rawPath] to the working directory.
  ///
  /// This is the only path ingestion point in the session. Every other member
  /// of this class works with the absolute, normalized paths it produces, so
  /// no other code path in this file may canonicalize. See [canonicalizePath]
  /// for the boundary contract.
  static String _ingestPath(String rawPath) =>
      canonicalizePath(rawPath, baseDirectory: Directory.current.path);

  /// The nullable companion to [_ingestPath].
  static String? _ingestOptionalPath(String? rawPath) =>
      rawPath == null ? null : _ingestPath(rawPath);

  /// Converts deprecated severity-only [deprecatedRules] into config
  /// patches and merges them with [configPatches].
  ///
  /// Returns an empty, unmodifiable const map when both inputs are empty.
  /// Throws an [ArgumentError] if both maps are non-empty.
  static Map<String, RuleConfigPatch> mergeDeprecatedRules(
    Map<String, AnalysisSeverity> deprecatedRules,
    Map<String, RuleConfigPatch> configPatches,
  ) {
    if (deprecatedRules.isEmpty && configPatches.isEmpty) {
      return const {};
    }
    if (deprecatedRules.isNotEmpty && configPatches.isNotEmpty) {
      throw ArgumentError(
        'Cannot specify both deprecated resolvedRules and new resolvedRuleConfigs. '
        'Please migrate all overrides to resolvedRuleConfigs.',
      );
    }
    final merged = Map<String, RuleConfigPatch>.from(configPatches);
    for (final MapEntry<String, AnalysisSeverity> entry in deprecatedRules.entries) {
      merged[entry.key] = RuleConfigPatch(severity: entry.value);
    }
    return merged;
  }

  final Configuration config;
  final Map<String, RuleConfigPatch> resolvedRuleConfigs;
  final String? ignoreFileOverride;
  final List<SkillRule> customRules;
  final bool printWarnings;
  final bool fastFail;
  final bool quiet;
  final bool generateBaseline;
  final bool fix;
  // TODO(reidbaker): Remove deprecated fixApply field on next major version bump.
  final bool fixApply;
  final OutputFormat format;
  final Reporter _reporter;
  final PubArchiveLoader _pubArchiveLoader;

  final List<ValidationResult> _results = [];
  final List<_ValidatedSkill> _validatedSkills = [];
  final Set<String> _renamedIgnorePaths = {};
  bool _anySkillRenamed = false;

  /// All validation results collected during this session.
  List<ValidationResult> get results => List.unmodifiable(_results);

  /// [config]'s targets with each `path` and `ignore_file` anchored once.
  ///
  /// `config` is static for the lifetime of a session, so the anchoring cost is
  /// paid up front instead of once per skill in [resolveRuleConfigsForPath] and
  /// [resolveIgnoreFile].
  final List<({String normalizedPath, String? normalizedIgnoreFile, LintTargetConfig config})>
  _normalizedDirectoryConfigs;

  bool _anyFailed = false;
  bool _anySkillsValidated = false;

  bool get anyFailed => _anyFailed;
  bool get anySkillsValidated => _anySkillsValidated;

  /// Reports that the [kind] of target at [normalizedPath] does not exist,
  /// explained with where it came from, and marks the session failed.
  void _reportMissingTarget(
    MissingTargetKind kind,
    String normalizedPath, {
    required LintTargetConfig? declaredBy,
    required String? cliText,
  }) {
    final MissingTargetDiagnostic diagnostic = missingTargetDiagnostic(
      kind: kind,
      resolvedPath: normalizedPath,
      workingDirectory: Directory.current.path,
      declaration: declaredBy == null ? null : declarationOf(declaredBy),
      cliText: cliText,
    );
    _reporter.onNoSkillsFound(diagnostic.text);
    _results.add(
      ValidationResult(
        validationErrors: [
          ValidationError(
            ruleId: Validator.pathDoesNotExist,
            file: diagnostic.file,
            message: diagnostic.text,
            markdownMessage: diagnostic.markdown,
            region: diagnostic.region,
            severity: AnalysisSeverity.error,
          ),
        ],
      ),
    );
    _anyFailed = true;
  }

  /// Validates a single skill directory passed via `--skill` / `-s`.
  ///
  /// Returns `true` if the caller should continue iterating, `false` to
  /// stop. Only a real validation failure under [fastFail] returns `false`;
  /// a missing directory contributes to [anyFailed] but still allows the
  /// caller to continue.
  ///
  /// Pass [declaredBy] when the path came from a configuration target, or
  /// [cliText] with the path as typed when it came from the command line, so
  /// that a missing directory is explained in terms the user wrote.
  Future<bool> processIndividualSkill(
    String skillPath, {
    LintTargetConfig? declaredBy,
    String? cliText,
  }) async {
    final String normalizedSkillPath = _ingestPath(skillPath);
    _reporter.onDirectoryEvaluating(normalizedSkillPath);
    final skillDir = Directory(normalizedSkillPath);

    if (!skillDir.existsSync()) {
      _reportMissingTarget(
        MissingTargetKind.skill,
        normalizedSkillPath,
        declaredBy: declaredBy,
        cliText: cliText,
      );
      return true;
    }

    final Map<String, RuleConfig> resolvedConfigs = resolveRuleConfigsForPath(normalizedSkillPath);
    final String? localIgnoreFile = resolveIgnoreFile(normalizedSkillPath);
    final validator = Validator(ruleConfigs: resolvedConfigs, customRules: customRules);

    final String ignorePath = _resolveIgnorePath(localIgnoreFile, skillDir);
    final SkillsIgnores ignores = await _loadIgnores(
      ignorePath,
      isCustomIgnoreFile: localIgnoreFile != null,
    );

    _anySkillsValidated = true;
    // The workflow adds no results, so this skill's result lands at
    // [resultIndex] when it is added below.
    final int resultIndex = _results.length;
    final ValidationResult finalResult = await _runValidationWorkflow(
      skillDir: skillDir,
      validator: validator,
      ignores: ignores,
      ignorePath: localIgnoreFile == null
          ? p.join(skillDir.path, defaultIgnoreFileName)
          : ignorePath,
      ignorePathFollowsSkillDir: localIgnoreFile == null,
      resultIndex: resultIndex,
    );
    _results.add(finalResult);

    final Directory effectiveSkillDir = finalResult.context?.directory ?? skillDir;
    final String effectiveSkillName = p.basename(effectiveSkillDir.path);
    final String effectiveIgnorePath = localIgnoreFile == null
        ? p.join(effectiveSkillDir.path, defaultIgnoreFileName)
        : ignorePath;
    if (generateBaseline) {
      await _saveBaseline(effectiveIgnorePath, ignores);
    } else {
      if (_renamedIgnorePaths.remove(effectiveIgnorePath)) {
        await _saveBaseline(effectiveIgnorePath, ignores);
      }
      final String fullPath = p.absolute(effectiveSkillDir.path);
      for (final IgnoreEntry ignore in ignores.skills[effectiveSkillName] ?? const []) {
        if (!ignore.used) {
          _reporter.onStaleIgnoreFound(
            ruleId: ignore.ruleId,
            skillName: effectiveSkillName,
            fullPath: fullPath,
          );
        }
      }
    }

    if (!finalResult.isValid) {
      _anyFailed = true;
      if (fastFail) {
        return false;
      }
    }
    return true;
  }

  /// Validates every skill directory under a root passed via
  /// `--skills-directory` / `-d`.
  ///
  /// Returns `true` if the caller should continue iterating, `false` to
  /// stop. Missing-root and listing-failure errors contribute to [anyFailed]
  /// but allow the caller to continue. After a successful iteration, returns
  /// `false` if [fastFail] is set and any failure has accumulated across the
  /// run so far.
  ///
  /// [declaredBy] and [cliText] describe where [rootPath] came from, as for
  /// [processIndividualSkill].
  Future<bool> processSkillRoot(
    String rootPath, {
    LintTargetConfig? declaredBy,
    String? cliText,
  }) async {
    final String normalizedRootPath = _ingestPath(rootPath);
    _reporter.onDirectoryEvaluating(normalizedRootPath);
    final rootDir = Directory(normalizedRootPath);

    if (!rootDir.existsSync()) {
      _reportMissingTarget(
        MissingTargetKind.skillsRoot,
        normalizedRootPath,
        declaredBy: declaredBy,
        cliText: cliText,
      );
      return true;
    }

    List<FileSystemEntity> entities;
    try {
      entities = await rootDir.list().toList();
    } on FileSystemException {
      _reporter.onDirectoryError(
        normalizedRootPath,
        'Failed to list children of: $normalizedRootPath',
      );
      _results.add(
        ValidationResult(
          validationErrors: [
            ValidationError(
              ruleId: Validator.pathDoesNotExist,
              file: normalizedRootPath,
              message: 'Failed to list children of: $normalizedRootPath',
              severity: AnalysisSeverity.error,
            ),
          ],
        ),
      );
      _anyFailed = true;
      return true;
    }
    entities.sort((a, b) => a.path.compareTo(b.path));

    // Keep a cache of loaded ignores to avoid loading/saving the same ignore file multiple times,
    // and to accumulate ignore usages correctly across all skills.
    final Map<String, SkillsIgnores> loadedIgnoresCache = {};

    for (final entity in entities) {
      if (entity is! Directory || p.basename(entity.path).startsWith('.')) {
        continue;
      }

      final bool shouldContinue = await _processRootSkillEntity(
        entity,
        rootDir,
        loadedIgnoresCache,
      );
      if (!shouldContinue) {
        break;
      }
    }

    await _finalizeIgnoresForRoot(loadedIgnoresCache, rootDir);
    await revalidateAfterRenames();

    return !(_anyFailed && fastFail);
  }

  /// Processes and validates a single skill directory ([entity]) located
  /// immediately inside a skills root directory ([rootDir]).
  Future<bool> _processRootSkillEntity(
    Directory entity,
    Directory rootDir,
    Map<String, SkillsIgnores> loadedIgnoresCache,
  ) async {
    // [rootDir] is already anchored, so its children are absolute as well.
    final String normalizedSkillPath = p.normalize(entity.path);
    final Map<String, RuleConfig> resolvedConfigs = resolveRuleConfigsForPath(normalizedSkillPath);
    final String? localIgnoreFile = resolveIgnoreFile(normalizedSkillPath);
    final validator = Validator(ruleConfigs: resolvedConfigs, customRules: customRules);

    final String ignorePath = _resolveIgnorePath(localIgnoreFile, rootDir);
    final SkillsIgnores ignores = await _getIgnoresForSkill(
      localIgnoreFile,
      rootDir,
      loadedIgnoresCache,
    );

    _anySkillsValidated = true;
    // The workflow adds no results, so this skill's result lands at
    // [resultIndex] when it is added below.
    final int resultIndex = _results.length;
    final ValidationResult finalResult = await _runValidationWorkflow(
      skillDir: entity,
      validator: validator,
      ignores: ignores,
      ignorePath: ignorePath,
      resultIndex: resultIndex,
    );
    _results.add(finalResult);

    if (!finalResult.isValid) {
      _anyFailed = true;
      if (fastFail) {
        return false;
      }
    }
    return true;
  }

  Future<SkillsIgnores> _getIgnoresForSkill(
    String? localIgnoreFile,
    Directory rootDir,
    Map<String, SkillsIgnores> loadedIgnoresCache,
  ) async {
    final String ignorePath = _resolveIgnorePath(localIgnoreFile, rootDir);

    if (loadedIgnoresCache.containsKey(ignorePath)) {
      return loadedIgnoresCache[ignorePath]!;
    }

    final SkillsIgnores ignores = await _loadIgnores(
      ignorePath,
      isCustomIgnoreFile: localIgnoreFile != null,
    );
    loadedIgnoresCache[ignorePath] = ignores;
    return ignores;
  }

  Future<void> _finalizeIgnoresForRoot(
    Map<String, SkillsIgnores> loadedIgnoresCache,
    Directory rootDir,
  ) async {
    for (final MapEntry<String, SkillsIgnores> entry in loadedIgnoresCache.entries) {
      final String ignorePath = entry.key;
      final SkillsIgnores ignores = entry.value;

      if (generateBaseline) {
        await _saveBaseline(ignorePath, ignores);
      } else {
        if (_renamedIgnorePaths.remove(ignorePath)) {
          await _saveBaseline(ignorePath, ignores);
        }
        _reportStaleIgnores(ignores, rootDir);
      }
    }
  }

  void _reportStaleIgnores(SkillsIgnores ignores, Directory rootDir) {
    for (final MapEntry<String, List<IgnoreEntry>> skillEntry in ignores.skills.entries) {
      final String skillName = skillEntry.key;
      for (final IgnoreEntry ignore in skillEntry.value) {
        if (!ignore.used) {
          final String fullPath = p.normalize(p.join(rootDir.path, skillName));
          _reporter.onStaleIgnoreFound(
            ruleId: ignore.ruleId,
            skillName: skillName,
            fullPath: fullPath,
          );
        }
      }
    }
  }

  /// If no skills were validated across the whole run, emit appropriate
  /// diagnostics and mark the session as failed.
  void reportNoSkillsValidated(List<String> rootPaths) {
    if (_anySkillsValidated) {
      return;
    }

    var foundSingleSkillPassedToD = false;
    for (final rootPath in rootPaths) {
      final String expandedRootPath = _ingestPath(rootPath);
      final skillMdFile = File(p.join(expandedRootPath, SkillContext.skillFileName));
      if (skillMdFile.existsSync()) {
        final message =
            'Directory "$expandedRootPath" appears to be an individual skill. '
            'Use --skill / -s instead of -d / --skills-directory.';
        _reporter.onIndividualSkillHint(message);
        _results.add(
          ValidationResult(
            validationErrors: [
              ValidationError(
                ruleId: Validator.pathDoesNotExist,
                file: expandedRootPath,
                message: message,
                severity: AnalysisSeverity.error,
              ),
            ],
          ),
        );
        foundSingleSkillPassedToD = true;
      }
    }
    if (!foundSingleSkillPassedToD) {
      const message = 'No skills found to validate in the specified directories.';
      _reporter.onNoSkillsFound(message);
      _results.add(
        ValidationResult(
          validationErrors: [
            ValidationError(
              ruleId: Validator.pathDoesNotExist,
              file: rootPaths.isNotEmpty ? rootPaths.first : '.',
              message: message,
              severity: AnalysisSeverity.error,
            ),
          ],
        ),
      );
    }
    _anyFailed = true;
  }

  // TODO(reidbaker): https://github.com/google/skills_lint.dart/issues/75
  @Deprecated('Use resolveRuleConfigsForPath instead')
  Map<String, AnalysisSeverity> resolveRulesForPath(String path) {
    return resolveRuleConfigsForPath(
      path,
    ).map((String key, RuleConfig value) => MapEntry(key, value.severity));
  }

  @visibleForTesting
  Map<String, RuleConfig> resolveRuleConfigsForPath(String path) {
    final String normalizedPath = _ingestPath(path);
    final resolvedConfigs = <String, RuleConfig>{};

    // Initialize with all checks defaults
    for (final CheckType check in RuleRegistry.allChecks) {
      resolvedConfigs[check.name] = RuleConfig(severity: check.defaultSeverity);
    }

    void applyPatchMap(Map<String, RuleConfigPatch> patches) {
      for (final MapEntry<String, RuleConfigPatch> entry in patches.entries) {
        final String ruleName = entry.key;
        final RuleConfigPatch patch = entry.value;

        final RuleConfig base =
            resolvedConfigs[ruleName] ?? const RuleConfig(severity: AnalysisSeverity.disabled);
        resolvedConfigs[ruleName] = patch.applyTo(base);
      }
    }

    // 1. Global Config (from YAML)
    applyPatchMap(config.ruleConfigs);

    // 2. Path-Specific Config (from YAML)
    for (final ({String normalizedPath, String? normalizedIgnoreFile, LintTargetConfig config})
        entry
        in _normalizedDirectoryConfigs) {
      if (_targetCovers(entry.normalizedPath, normalizedPath)) {
        applyPatchMap(entry.config.ruleConfigs);
      }
    }

    // 3. Overrides (CLI flags or API caller) take highest precedence
    applyPatchMap(resolvedRuleConfigs);

    return resolvedConfigs;
  }

  @visibleForTesting
  String? resolveIgnoreFile(String path) {
    final String normalizedPath = _ingestPath(path);
    if (ignoreFileOverride != null) {
      return ignoreFileOverride;
    }
    String? resolvedIgnoreFile;
    for (final ({String normalizedPath, String? normalizedIgnoreFile, LintTargetConfig config})
        entry
        in _normalizedDirectoryConfigs) {
      if (_targetCovers(entry.normalizedPath, normalizedPath)) {
        resolvedIgnoreFile = entry.normalizedIgnoreFile ?? resolvedIgnoreFile;
      }
    }
    return resolvedIgnoreFile;
  }

  /// Whether a configuration target at [targetPath] applies to [skillPath].
  ///
  /// Both arguments are absolute, so the comparison is a pure path operation
  /// that never consults the working directory.
  static bool _targetCovers(String targetPath, String skillPath) =>
      isAtOrWithin(targetPath, skillPath);

  String _resolveIgnorePath(String? localIgnoreFile, Directory rootDir) {
    // [localIgnoreFile] arrives anchored from [resolveIgnoreFile] or from
    // [ignoreFileOverride], both of which pass through [_ingestPath].
    return localIgnoreFile ?? p.join(rootDir.path, defaultIgnoreFileName);
  }

  /// Loads the ignore JSON from [ignorePath], returning the parsed [SkillsIgnores].
  ///
  /// If [isCustomIgnoreFile] is true and the file does not exist, generates an
  /// empty baseline file on disk.
  Future<SkillsIgnores> _loadIgnores(String ignorePath, {required bool isCustomIgnoreFile}) async {
    final file = File(ignorePath);

    if (file.existsSync()) {
      final storage = SkillsIgnoresStorage();
      return storage.load(ignorePath);
    }

    // If a custom ignore file was specified but not found, create an empty one
    // so the user can start adding ignores to it.
    if (isCustomIgnoreFile) {
      _log.warning('File not found generating-baseline');
      try {
        await file.writeAsString(jsonEncode({SkillsIgnores.skillsKey: <String, dynamic>{}}));
      } on FileSystemException {
        // Ignore write errors, we will just return empty ignores.
      }
    }

    return SkillsIgnores(skills: {});
  }

  /// Marks the errors in [result] that [ignores] covers.
  ///
  /// [skillDir] is the anchored directory of the skill under validation, and
  /// gives each error a portable name to compare against.
  void _applyIgnores(ValidationResult result, List<IgnoreEntry> ignores, Directory skillDir) {
    final List<({IgnoreEntry entry, String normalizedFileName})> preNormalizedIgnores = [
      for (final ignore in ignores)
        (entry: ignore, normalizedFileName: p.normalize(ignore.fileName)),
    ];

    for (final ValidationError error in result.validationErrors) {
      if (error.isIgnored) {
        continue;
      }
      final String portableName = baselineFileName(error.file, skillDir);
      final String absoluteName = _absoluteErrorFile(error.file, skillDir);
      for (final pair in preNormalizedIgnores) {
        final IgnoreEntry ignore = pair.entry;
        if (ignore.ruleId == error.ruleId &&
            _ignoreCovers(pair.normalizedFileName, portableName, absoluteName)) {
          error.isIgnored = true;
          ignore.used = true;
          break;
        }
      }
    }
  }

  /// Returns the `file_name` to store in a baseline entry for an error that a
  /// rule reported on [errorFile] while validating [skillDir].
  ///
  /// Both writing a baseline and matching against one call this, so that the
  /// two agree on a single spelling.
  ///
  /// The result is relative to [skillDir]: `SKILL.md` for an error on a file in
  /// the skill, and `.` for an error on the skill directory itself, which is
  /// what a rule such as `path-does-not-exist` reports. Keeping the name
  /// relative lets a committed baseline match on any machine and from any
  /// working directory. A path outside [skillDir] is returned as reported,
  /// since no relative name would describe it.
  @visibleForTesting
  static String baselineFileName(String errorFile, Directory skillDir) {
    final String normalized = p.normalize(errorFile);
    final String skillPath = p.normalize(skillDir.path);
    if (p.isAbsolute(normalized) && isAtOrWithin(skillPath, normalized)) {
      return p.relative(normalized, from: skillPath);
    }
    return normalized;
  }

  /// Where an error reported on [errorFile] sits on disk.
  static String _absoluteErrorFile(String errorFile, Directory skillDir) {
    final String normalized = p.normalize(errorFile);
    if (p.isAbsolute(normalized)) {
      return normalized;
    }
    return p.normalize(p.join(skillDir.path, normalized));
  }

  /// Whether [ignoreFileName] covers an error named [portableName].
  ///
  /// Baselines written before names were stored relative to the skill
  /// directory hold the path as it was spelled on the command line. Those
  /// entries keep matching while [absoluteName] ends with them.
  static bool _ignoreCovers(String ignoreFileName, String portableName, String absoluteName) {
    if (ignoreFileName == portableName || p.equals(ignoreFileName, absoluteName)) {
      return true;
    }
    return _isPathSuffix(ignoreFileName, absoluteName);
  }

  /// Whether [candidate] names the trailing segments of [full].
  static bool _isPathSuffix(String candidate, String full) {
    final List<String> candidateSegments = p.split(candidate);
    final List<String> fullSegments = p.split(full);
    if (candidateSegments.isEmpty || candidateSegments.length >= fullSegments.length) {
      return false;
    }
    final int offset = fullSegments.length - candidateSegments.length;
    for (var i = 0; i < candidateSegments.length; i++) {
      if (candidateSegments[i] != fullSegments[offset + i]) {
        return false;
      }
    }
    return true;
  }

  /// Validates [skillDir], applies fixes if requested, and (when
  /// [generateBaseline] is set) updates [ignores] in memory with any new
  /// baseline entries for this skill. The caller is responsible for
  /// persisting [ignores] to disk once after all skills are processed —
  /// see [_saveBaseline].
  Future<ValidationResult> _runValidationWorkflow({
    required Directory skillDir,
    required Validator validator,
    required SkillsIgnores ignores,
    required String ignorePath,
    required int resultIndex,
    bool ignorePathFollowsSkillDir = false,
  }) async {
    final String skillName = p.basename(skillDir.path);
    final List<IgnoreEntry> skillIgnores = ignores.skills[skillName] ?? [];

    final ValidationResult result = await _validateSingleSkill(
      skillDir: skillDir,
      validator: validator,
      skillIgnores: skillIgnores,
    );

    final ValidationResult finalResult = await _applyFixesIfNeeded(
      skillDir: skillDir,
      result: result,
      validator: validator,
      skillIgnores: skillIgnores,
      ignores: ignores,
      ignorePath: ignorePath,
      ignorePathFollowsSkillDir: ignorePathFollowsSkillDir,
    );

    final Directory effectiveSkillDir = finalResult.context?.directory ?? skillDir;
    final String effectiveName = p.basename(effectiveSkillDir.path);
    final String effectiveIgnorePath = ignorePathFollowsSkillDir
        ? p.join(effectiveSkillDir.path, defaultIgnoreFileName)
        : ignorePath;
    _validatedSkills.add(
      _ValidatedSkill(
        resultIndex: resultIndex,
        skillDir: effectiveSkillDir,
        validator: validator,
        ignores: ignores,
        ignorePath: effectiveIgnorePath,
      ),
    );
    if (fixApply && identical(finalResult, result)) {
      _reporter.onSkillValidationComplete(result);
    }

    if (generateBaseline) {
      _updateBaselineForSkill(ignores, finalResult, effectiveName, effectiveSkillDir);
    }

    return finalResult;
  }

  Future<ValidationResult> _validateSingleSkill({
    required Directory skillDir,
    required Validator validator,
    required List<IgnoreEntry> skillIgnores,
  }) async {
    final String skillName = p.basename(skillDir.path);
    _reporter.onSkillEvaluating(skillName);
    final ValidationResult result = await validator.validate(
      skillDir,
      pubArchive: await _pubArchiveFor(skillDir, validator),
    );
    _applyIgnores(result, skillIgnores, skillDir);
    // With --fix, the result that counts is the one after the fixes are done.
    if (!fixApply) {
      _reporter.onSkillValidationComplete(result);
    }
    return result;
  }

  /// The files pub publishes for the package that holds [skillDir], or
  /// `null` when no rule in [validator] needs them.
  ///
  /// Building the archive runs `dart pub publish`, so the session does it
  /// only for skills that enable [PubArchiveIncludesSkillRule].
  Future<PubArchive?> _pubArchiveFor(Directory skillDir, Validator validator) async {
    final bool needsArchive = validator.rules.any(
      (SkillRule rule) => rule.name == PubArchiveIncludesSkillRule.ruleName,
    );
    if (!needsArchive) {
      return null;
    }
    return _pubArchiveLoader.archiveFor(skillDir);
  }

  Future<ValidationResult> _applyFixesIfNeeded({
    required Directory skillDir,
    required ValidationResult result,
    required Validator validator,
    required List<IgnoreEntry> skillIgnores,
    required SkillsIgnores ignores,
    required String ignorePath,
    required bool ignorePathFollowsSkillDir,
  }) async {
    if (!fix && !fixApply) {
      return result;
    }

    final SkillContext? context = result.context;
    if (context == null) {
      return result;
    }

    final skillMdFile = File(p.join(skillDir.path, SkillContext.skillFileName));
    if (!skillMdFile.existsSync()) {
      return result;
    }

    final FixOutcome outcome = await SkillFixer(
      validator: validator,
      applyIgnores: (ValidationResult candidate) =>
          _applyIgnores(candidate, skillIgnores, skillDir),
      onFixFailed: (String ruleName, Object error) =>
          _reporter.onFixFailed(ruleName: ruleName, error: error),
    ).fix(result);
    final String currentDirectoryName = p.basename(skillDir.path);
    for (final SkippedFix skipped in outcome.skippedFixes) {
      _reporter.onFixSkipped(currentDirectoryName, skipped);
    }
    if (!outcome.settled) {
      _reporter.onFixesDidNotSettle(skillName: currentDirectoryName, passes: SkillFixer.maxPasses);
    }

    if (outcome.content == context.rawContent) {
      return result;
    }

    if (fixApply) {
      await skillMdFile.writeAsString(outcome.content);
      _reporter.onFixesWritten(currentDirectoryName, ruleNames: outcome.appliedRuleNames);

      // A blocked rename is tried again so that the collision is reported.
      final Directory fixedSkillDir = await _renameSkillDirectory(
        skillDir,
        outcome.blockedDirectoryName ?? outcome.directoryName,
      );
      final String fixedName = p.basename(fixedSkillDir.path);
      _recordSkillRename(
        oldName: currentDirectoryName,
        newName: fixedName,
        fixedSkillDir: fixedSkillDir,
        ignores: ignores,
        ignorePath: ignorePath,
        ignorePathFollowsSkillDir: ignorePathFollowsSkillDir,
      );
      if (fixedName != currentDirectoryName) {
        // The archive lists files by path, so a rename makes it stale.
        _pubArchiveLoader.clear();
      }
      final List<IgnoreEntry> fixedIgnores = ignores.skills[fixedName] ?? skillIgnores;
      final ValidationResult newResult = await validator.validate(
        fixedSkillDir,
        pubArchive: await _pubArchiveFor(fixedSkillDir, validator),
      );
      _applyIgnores(newResult, fixedIgnores, fixedSkillDir);
      _reporter.onFixedSkillValidationComplete(newResult);
      return newResult;
    }

    _reporter.onDryRunProposed(
      skillName: currentDirectoryName,
      targetSkillName: outcome.directoryName,
      originalContent: context.rawContent,
      currentContent: outcome.content,
    );
    _reporter.onFixedSkillValidationComplete(outcome.result, dryRun: true);
    return result;
  }

  void _recordSkillRename({
    required String oldName,
    required String newName,
    required Directory fixedSkillDir,
    required SkillsIgnores ignores,
    required String ignorePath,
    required bool ignorePathFollowsSkillDir,
  }) {
    if (newName == oldName) {
      return;
    }
    _anySkillRenamed = true;
    if (!ignores.renameSkill(oldName, newName)) {
      return;
    }
    final String targetIgnorePath = ignorePathFollowsSkillDir
        ? p.join(fixedSkillDir.path, defaultIgnoreFileName)
        : ignorePath;
    if (File(targetIgnorePath).existsSync()) {
      _renamedIgnorePaths.add(targetIgnorePath);
    }
  }

  /// Renames [skillDir] to [newDirectoryName], and returns the skill
  /// directory as it is afterwards.
  ///
  /// Returns [skillDir] when it already has that name or the rename fails.
  Future<Directory> _renameSkillDirectory(Directory skillDir, String newDirectoryName) async {
    final String currentDirectoryName = p.basename(skillDir.path);
    if (newDirectoryName == currentDirectoryName) {
      return skillDir;
    }

    final String parentPath = p.dirname(skillDir.path);
    final String newDirPath = p.join(parentPath, newDirectoryName);
    final newDir = Directory(newDirPath);

    if (SkillFixer.isNameTaken(skillDir, newDirectoryName)) {
      _reporter.onRenameTargetExists(
        oldSkillName: currentDirectoryName,
        targetSkillName: newDirectoryName,
        destinationPath: newDir.path,
      );
      return skillDir;
    }

    final Directory renamed;
    try {
      renamed = await skillDir.rename(newDirPath);
    } on FileSystemException catch (e) {
      _reporter.onRenameFailed(
        oldSkillName: currentDirectoryName,
        targetSkillName: newDirectoryName,
        error: e,
      );
      return skillDir;
    }
    _reporter.onSkillRenamed(currentDirectoryName, newDirectoryName);
    return renamed;
  }

  /// Mutates [ignores] in place to add baseline entries for any non-ignored
  /// errors in [result] under the [skillName] key. Pure in-memory operation
  /// — pair with [_saveBaseline] to persist changes.
  void _updateBaselineForSkill(
    SkillsIgnores ignores,
    ValidationResult result,
    String skillName,
    Directory skillDir,
  ) {
    final List<IgnoreEntry> currentSkillIgnores = ignores.skills[skillName] ?? [];
    final currentSkillSeen = <String>{};
    for (final ignore in currentSkillIgnores) {
      currentSkillSeen.add('${ignore.ruleId}:${ignore.fileName}');
    }

    for (final ValidationError error in result.validationErrors) {
      if (!error.isIgnored) {
        final String fileName = baselineFileName(error.file, skillDir);
        final key = '${error.ruleId}:$fileName';
        if (currentSkillSeen.contains(key)) {
          continue;
        }
        currentSkillSeen.add(key);

        currentSkillIgnores.add(IgnoreEntry(ruleId: error.ruleId, fileName: fileName));
      }
    }

    if (currentSkillIgnores.isNotEmpty) {
      ignores.skills[skillName] = currentSkillIgnores;
    } else {
      ignores.skills.remove(skillName);
    }
  }

  /// Writes [ignores] to [ignorePath]. Write failures are logged at warning
  /// level and otherwise swallowed so a single I/O error does not abort the
  /// rest of the run.
  Future<void> _saveBaseline(String ignorePath, SkillsIgnores ignores) async {
    try {
      await SkillsIgnoresStorage().save(ignorePath, ignores);
    } on FileSystemException catch (e) {
      _reporter.onBaselineFailed(ignorePath, e);
    }
  }

  /// Emits the formatted validation output (SARIF or JSON) to [sink] (defaults to [stdout]).
  void emitFormattedOutput([StringSink? sink]) {
    if (sink != null) {
      Reporter.fromFormat(format, out: sink).onSessionComplete(_results, customRules: customRules);
    } else {
      _reporter.onSessionComplete(_results, customRules: customRules);
    }
  }

  /// Formats all accumulated validation results according to [format].
  String formatOutput({bool pretty = true}) {
    switch (format) {
      case OutputFormat.sarif:
        return toSarifJson(pretty: pretty);
      case OutputFormat.json:
        return toJsonOutput(pretty: pretty);
      case OutputFormat.text:
        return toTextOutput();
    }
  }

  /// Formats the accumulated validation results as human-readable text.
  String toTextOutput() {
    final buffer = StringBuffer();
    final textReporter = TextReporter(
      out: buffer,
      err: buffer,
      quiet: quiet,
      printWarnings: printWarnings,
    );
    for (final ValidationResult result in _results) {
      final String skillName = result.context != null
          ? p.basename(result.context!.directory.path)
          : 'skill';
      textReporter.onSkillEvaluating(skillName);
      textReporter.onSkillValidationComplete(result);
    }
    return buffer.toString();
  }

  /// Converts accumulated validation results into a SARIF log.
  SarifLog _toSarif({String? toolVersion, String? rootDirectory}) {
    return SarifSerializer.toSarifLog(
      _results,
      toolVersion: toolVersion,
      checkTypes: RuleRegistry.allChecks,
      customRules: customRules,
      rootDirectory: rootDirectory,
    );
  }

  /// Serializes the accumulated validation results as a SARIF JSON string.
  String toSarifJson({bool pretty = true, String? toolVersion, String? rootDirectory}) {
    final SarifLog sarif = _toSarif(toolVersion: toolVersion, rootDirectory: rootDirectory);
    final encoder = pretty ? const JsonEncoder.withIndent('  ') : const JsonEncoder();
    return encoder.convert(sarif.toJson());
  }

  /// Serializes the accumulated validation results as a raw JSON array string.
  String toJsonOutput({bool pretty = true}) {
    final List<Map<String, Object?>> jsonList = _results.map((r) => r.toJson()).toList();
    final encoder = pretty ? const JsonEncoder.withIndent('  ') : const JsonEncoder();
    return encoder.convert(jsonList);
  }

  /// Re-validates every processed skill from disk after a `--fix` run that
  /// renamed at least one skill directory.
  ///
  /// Renaming a later skill can break a relative link in a sibling skill that
  /// was already validated. Re-validating once after all renames catches any
  /// new diagnostics, reports them, and updates [results] and [anyFailed].
  /// It runs only when at least one skill directory was renamed and more
  /// than one skill was validated.
  Future<void> revalidateAfterRenames() async {
    if (!_anySkillRenamed || _validatedSkills.length <= 1) {
      return;
    }
    _anySkillRenamed = false;
    _reporter.onRecheckAfterRenames();
    final baselinesToSave = <String, SkillsIgnores>{};
    // The renames changed files on disk, so an archive built earlier may be
    // stale.
    _pubArchiveLoader.clear();

    for (final _ValidatedSkill entry in _validatedSkills) {
      if (!entry.skillDir.existsSync()) {
        continue;
      }
      final String skillName = p.basename(entry.skillDir.path);
      final List<IgnoreEntry> skillIgnores = entry.ignores.skills[skillName] ?? const [];
      final ValidationResult previous = _results[entry.resultIndex];
      final ValidationResult fresh = await entry.validator.validate(
        entry.skillDir,
        pubArchive: await _pubArchiveFor(entry.skillDir, entry.validator),
      );
      _applyIgnores(fresh, skillIgnores, entry.skillDir);
      _results[entry.resultIndex] = fresh;

      if (generateBaseline) {
        _updateBaselineForSkill(entry.ignores, fresh, skillName, entry.skillDir);
        baselinesToSave[entry.ignorePath] = entry.ignores;
      }

      if (!_sameDiagnostics(previous, fresh)) {
        _reporter.onSkillEvaluating(skillName);
        _reporter.onFixedSkillValidationComplete(fresh);
      }
    }
    // Every failure adds an invalid result, so a skill that a sibling's
    // rename made valid no longer fails the run.
    _anyFailed = _results.any((ValidationResult result) => !result.isValid);

    for (final MapEntry<String, SkillsIgnores> saveEntry in baselinesToSave.entries) {
      await _saveBaseline(saveEntry.key, saveEntry.value);
    }
  }

  static bool _sameDiagnostics(ValidationResult a, ValidationResult b) =>
      _sameStrings(a.errors, b.errors) && _sameStrings(a.warnings, b.warnings);

  static bool _sameStrings(List<String> a, List<String> b) =>
      a.length == b.length && Iterable<int>.generate(a.length).every((i) => a[i] == b[i]);
}

class _ValidatedSkill {
  const _ValidatedSkill({
    required this.resultIndex,
    required this.skillDir,
    required this.validator,
    required this.ignores,
    required this.ignorePath,
  });

  final int resultIndex;
  final Directory skillDir;
  final Validator validator;
  final SkillsIgnores ignores;
  final String ignorePath;
}
