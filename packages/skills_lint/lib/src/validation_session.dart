// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'config_parser.dart';
import 'fixable_rule.dart';
import 'models/analysis_severity.dart';
import 'models/check_type.dart';
import 'models/ignore_entry.dart';
import 'models/rule_config.dart';
import 'models/skill_context.dart';
import 'models/skill_rule.dart';
import 'models/skills_ignores.dart';
import 'models/validation_error.dart';
import 'path_utils.dart';
import 'rule_registry.dart';
import 'skills_ignores_storage.dart';
import 'validator.dart';

final _log = Logger('skills_lint');

/// Default filename for the per-run ignore baseline file.
///
/// Referenced both by production code (the `--generate-baseline` help text in
/// the CLI) and by tests, so this is intentionally not `@visibleForTesting`.
const defaultIgnoreFileName = 'skills_lint_ignore.json';

@visibleForTesting
const skillIsValidMsg = '  Skill is valid.';
@visibleForTesting
const skillIsInvalidMsg = '  Skill is invalid:';
@visibleForTesting
const warningsMsg = 'Warnings:';

@visibleForTesting
const evaluatingDirMsg = 'Evaluating directory:';

@visibleForTesting
const directoryErrorMsg = 'Directory error:';

/// Per-invocation state and orchestration for skill validation.
///
/// One session is constructed per CLI invocation (or embedded call). The
/// session aggregates configuration parameters, custom rules, ignores, and CLI overrides,
/// then orchestrates the validation of multiple target skill directories.
///
/// ## Path Canonicalization Contract
///
/// [ValidationSession] operates strictly on canonical absolute paths. Paths crossing into
/// the session from the CLI, configuration files, or external API callers are canonicalized
/// at ingestion boundaries, ensuring that all path resolution and comparison logic
/// (such as rule resolution via `p.isWithin` or `p.equals`) operates uniformly.
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
  ValidationSession({
    required this.config,
    // TODO(reidbaker): https://github.com/google/skills_lint.dart/issues/179
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
    required this.fixApply,
  }) : resolvedRuleConfigs = _mergeDeprecatedRules(resolvedRules, resolvedRuleConfigs),
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

  static Map<String, RuleConfigPatch> _mergeDeprecatedRules(
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
  final bool fixApply;

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

  /// Validates a single skill directory passed via `--skill` / `-s`.
  ///
  /// Returns `true` if the caller should continue iterating, `false` to
  /// stop. Only a real validation failure under [fastFail] returns `false`;
  /// a missing directory contributes to [anyFailed] but still allows the
  /// caller to continue.
  Future<bool> processIndividualSkill(String skillPath) async {
    final String normalizedSkillPath = _ingestPath(skillPath);
    if (!quiet) {
      _log.info('$evaluatingDirMsg $normalizedSkillPath');
    }
    final skillDir = Directory(normalizedSkillPath);

    if (!skillDir.existsSync()) {
      _log.severe('Specified skill directory does not exist: $normalizedSkillPath');
      _anyFailed = true;
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
    final String skillName = p.basename(skillDir.path);
    final List<IgnoreEntry> skillIgnores = ignores.skills[skillName] ?? [];

    _anySkillsValidated = true;
    final ValidationResult finalResult = await _runValidationWorkflow(
      skillDir: skillDir,
      validator: validator,
      ignores: ignores,
    );

    if (generateBaseline) {
      await _saveBaseline(ignorePath, ignores);
    } else {
      final String fullPath = p.absolute(skillDir.path);
      for (final ignore in skillIgnores) {
        if (!ignore.used) {
          _log.info(
            "Stale ignore entry found for rule '${ignore.ruleId}' in skill "
            "'$skillName' at '$fullPath'. Consider removing it.",
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
  Future<bool> processSkillRoot(String rootPath) async {
    final String normalizedRootPath = _ingestPath(rootPath);
    if (!quiet) {
      _log.info('$evaluatingDirMsg $normalizedRootPath');
    }
    final rootDir = Directory(normalizedRootPath);

    if (!rootDir.existsSync()) {
      _log.severe('Specified root directory does not exist: $normalizedRootPath');
      _anyFailed = true;
      return true;
    }

    List<FileSystemEntity> entities;
    try {
      entities = await rootDir.list().toList();
    } catch (_) {
      _log.severe('  $directoryErrorMsg');
      _log.severe('    - Failed to list children of: $normalizedRootPath');
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

    return !(_anyFailed && fastFail);
  }

  /// Processes and validates a single skill directory ([entity]) located
  /// immediately inside a skills root directory ([rootDir]).
  ///
  /// In this context, "root" refers to the container directory passed via
  /// `--skills-directory` / `-d` (represented by [rootDir]), which holds one or
  /// more child skill folders. [entity] is an individual skill folder within
  /// that root container.
  ///
  /// Returns `true` if iteration over the remaining skills in [rootDir] should
  /// continue, or `false` to abort early when [fastFail] is enabled and this
  /// skill failed validation.
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

    final SkillsIgnores ignores = await _getIgnoresForSkill(
      localIgnoreFile,
      rootDir,
      loadedIgnoresCache,
    );

    _anySkillsValidated = true;
    final ValidationResult finalResult = await _runValidationWorkflow(
      skillDir: entity,
      validator: validator,
      ignores: ignores,
    );

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
          _log.info(
            "Stale ignore entry found for rule '${ignore.ruleId}' in skill "
            "'$skillName' at '$fullPath'. Consider removing it.",
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
        _log.severe(
          'Directory "$expandedRootPath" appears to be an individual skill. '
          'Use --skill / -s instead of -d / --skills-directory.',
        );
        foundSingleSkillPassedToD = true;
      }
    }
    if (!foundSingleSkillPassedToD) {
      _log.severe('No skills found to validate in the specified directories.');
    }
    _anyFailed = true;
  }

  // TODO(reidbaker): https://github.com/google/skills_lint.dart/issues/179
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
      p.equals(targetPath, skillPath) || p.isWithin(targetPath, skillPath);

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
      } catch (_) {
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
    // Pre-normalize ignore filenames once so the inner loop below is a
    // straight string comparison instead of repeated path normalization.
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

  /// The name recorded in a baseline for an error reported on [errorFile].
  ///
  /// A rule reports a name relative to the skill directory, such as `SKILL.md`,
  /// an absolute path to a file inside the skill, or the skill directory itself
  /// when the error describes the skill as a whole. All three collapse to a
  /// name relative to the skill directory, `.` in the last case, so that a
  /// baseline committed to a repository matches on any machine and from any
  /// working directory. A path outside [skillDir] is kept as reported.
  @visibleForTesting
  static String baselineFileName(String errorFile, Directory skillDir) {
    final String normalized = p.normalize(errorFile);
    final String skillPath = p.normalize(skillDir.path);
    if (p.isAbsolute(normalized) && _isAtOrWithin(skillPath, normalized)) {
      return p.relative(normalized, from: skillPath);
    }
    return normalized;
  }

  /// Whether [candidate] is [parent] or sits inside it.
  ///
  /// `p.isWithin` reports `false` for a directory compared against itself, so
  /// an error reported on the skill directory needs the equality case to reach
  /// `p.relative`, which names a directory relative to itself as `.`.
  static bool _isAtOrWithin(String parent, String candidate) =>
      p.equals(parent, candidate) || p.isWithin(parent, candidate);

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
    );

    if (generateBaseline) {
      final String effectiveName = p.basename(finalResult.context?.directory.path ?? skillDir.path);
      _updateBaselineForSkill(
        ignores,
        finalResult,
        effectiveName,
        finalResult.context?.directory ?? skillDir,
      );
    }

    return finalResult;
  }

  Future<ValidationResult> _validateSingleSkill({
    required Directory skillDir,
    required Validator validator,
    required List<IgnoreEntry> skillIgnores,
  }) async {
    final String skillName = p.basename(skillDir.path);
    if (!quiet) {
      _log.info('--- Validating skill: $skillName ---');
    }
    final ValidationResult result = await validator.validate(skillDir);
    _applyIgnores(result, skillIgnores, skillDir);
    _printValidationResult(result);
    return result;
  }

  Future<ValidationResult> _applyFixesIfNeeded({
    required Directory skillDir,
    required ValidationResult result,
    required Validator validator,
    required List<IgnoreEntry> skillIgnores,
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

    final String fixedContent = await _runFixableRules(
      context: context,
      result: result,
      validator: validator,
    );

    if (fixedContent == context.rawContent) {
      return result;
    }

    return _handleFixResult(
      skillDir: skillDir,
      skillMdFile: skillMdFile,
      originalContent: context.rawContent,
      currentContent: fixedContent,
      validator: validator,
      skillIgnores: skillIgnores,
      fallbackResult: result,
    );
  }

  /// Runs all fixable rules against [context.rawContent] sequentially and
  /// returns the resulting content string.
  Future<String> _runFixableRules({
    required SkillContext context,
    required ValidationResult result,
    required Validator validator,
  }) async {
    String currentContent = context.rawContent;

    for (final SkillRule rule in validator.rules) {
      if (rule is! FixableRule) {
        continue;
      }
      final bool hasErrors = result.validationErrors.any(
        (e) => e.ruleId == rule.name && !e.isIgnored,
      );
      if (!hasErrors) {
        continue;
      }

      try {
        final String newContent = await rule.fix(
          SkillContext.skillFileName,
          currentContent,
          context.directory,
        );
        currentContent = newContent;
      } catch (e) {
        _log.severe("  Failed to apply fix for rule '${rule.name}': $e");
      }
    }

    return currentContent;
  }

  Future<ValidationResult> _handleFixResult({
    required Directory skillDir,
    required File skillMdFile,
    required String originalContent,
    required String currentContent,
    required Validator validator,
    required List<IgnoreEntry> skillIgnores,
    required ValidationResult fallbackResult,
  }) async {
    final String oldSkillName = p.basename(skillDir.path);
    final String? oldFrontmatterName = _extractSkillName(originalContent);
    final String? targetSkillName = _extractSkillName(currentContent);
    final bool nameChangedByFix =
        oldFrontmatterName != null &&
        targetSkillName != null &&
        oldFrontmatterName != targetSkillName;

    if (fixApply) {
      await skillMdFile.writeAsString(currentContent);
      if (!quiet) {
        _log.info('  Applied fixes for $oldSkillName');
      }

      final Directory effectiveSkillDir = nameChangedByFix
          ? await _alignSkillDirectory(
              skillDir: skillDir,
              oldSkillName: oldSkillName,
              targetSkillName: targetSkillName,
            )
          : skillDir;

      final ValidationResult newResult = await validator.validate(effectiveSkillDir);
      _applyIgnores(newResult, skillIgnores, effectiveSkillDir);
      return newResult;
    }

    if (fix && !quiet) {
      _logDryRunFix(
        oldSkillName: oldSkillName,
        targetSkillName: nameChangedByFix ? targetSkillName : null,
        originalContent: originalContent,
        currentContent: currentContent,
      );
    }
    return fallbackResult;
  }

  /// Aligns the skill's parent directory name on disk with the frontmatter
  /// [targetSkillName] if the name changed during the fix process.
  ///
  /// Returns the renamed [Directory] if the rename succeeded, or [skillDir] if
  /// no rename was needed or if the destination directory already exists.
  Future<Directory> _alignSkillDirectory({
    required Directory skillDir,
    required String oldSkillName,
    required String? targetSkillName,
  }) async {
    if (targetSkillName == null || targetSkillName.isEmpty || targetSkillName == oldSkillName) {
      return skillDir;
    }

    final String parentPath = p.dirname(skillDir.path);
    final String newDirPath = p.join(parentPath, targetSkillName);
    final newDir = Directory(newDirPath);

    if (newDir.existsSync()) {
      _log.severe(
        '  Cannot rename skill directory from $oldSkillName to $targetSkillName: '
        'destination directory ${newDir.path} already exists.',
      );
      return skillDir;
    }

    try {
      final Directory renamed = await skillDir.rename(newDirPath);
      if (!quiet) {
        _log.info('  Renamed skill directory: $oldSkillName -> $targetSkillName');
      }
      return renamed;
    } catch (e) {
      _log.severe('  Failed to rename skill directory from $oldSkillName to $targetSkillName: $e');
      return skillDir;
    }
  }

  /// Logs proposed frontmatter diffs and proposed directory renames to stdout
  /// when running fixes in dry-run mode (`--fix --dry-run`).
  void _logDryRunFix({
    required String oldSkillName,
    required String? targetSkillName,
    required String originalContent,
    required String currentContent,
  }) {
    _log.info('  [Dry Run] Proposed changes for $oldSkillName (SKILL.md):');
    _printDiff(originalContent, currentContent);
    if (targetSkillName != null && targetSkillName.isNotEmpty && targetSkillName != oldSkillName) {
      _log.info('  [Dry Run] Proposed directory rename: $oldSkillName -> $targetSkillName');
    }
  }

  /// Extracts the frontmatter `name:` string from raw [content], returning
  /// `null` if the content lacks frontmatter or fails YAML parsing.
  static String? _extractSkillName(String content) {
    final RegExpMatch? match = SkillContext.skillStartRegex.firstMatch(content);
    if (match != null) {
      try {
        final Object? doc = loadYaml(match.group(1)!);
        if (doc is YamlMap && doc['name'] != null) {
          return doc['name'].toString().trim();
        }
      } catch (_) {
        // Ignore YAML parsing errors during fix post-processing.
      }
    }
    return null;
  }

  /// Prints a simple line-by-line diff between [original] and [modified].
  ///
  /// **Limitation**: This naive diff algorithm does not handle line additions
  /// or removals well, as it compares lines at the same index. It is
  /// sufficient for current fixers that only modify existing lines, but
  /// should be replaced with a more robust diffing solution (e.g.,
  /// `package:diff`) if future fixers add or remove lines.
  void _printDiff(String original, String modified) {
    final List<String> origLines = original.split('\n');
    final List<String> modLines = modified.split('\n');
    final int maxLines = origLines.length > modLines.length ? origLines.length : modLines.length;
    for (var i = 0; i < maxLines; i++) {
      final String orig = i < origLines.length ? origLines[i] : '';
      final String mod = i < modLines.length ? modLines[i] : '';
      if (orig != mod) {
        if (orig.isNotEmpty) {
          _log.info('- Line ${i + 1}: $orig');
        }
        if (mod.isNotEmpty) {
          _log.info('+ Line ${i + 1}: $mod');
        }
      }
    }
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
    } catch (e) {
      _log.warning('Failed to generate baseline file at $ignorePath: $e');
    }
  }

  void _printValidationResult(ValidationResult result) {
    if (result.isValid) {
      if (!quiet) {
        _log.info('  $skillIsValidMsg');
      }
    } else {
      _log.severe('  $skillIsInvalidMsg');
      for (final String error in result.errors) {
        _log.severe('    - $error');
      }
    }

    if (printWarnings && result.warnings.isNotEmpty) {
      _log.warning('  $warningsMsg');
      for (final String warning in result.warnings) {
        _log.warning('    - $warning');
      }
    }
  }
}
