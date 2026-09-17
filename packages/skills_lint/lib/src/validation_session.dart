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
import 'models/output_format.dart';
import 'models/rule_config.dart';
import 'models/sarif/sarif.dart';
import 'models/skill_context.dart';
import 'models/skill_rule.dart';
import 'models/skills_ignores.dart';
import 'models/validation_error.dart';
import 'path_utils.dart';
import 'reporters/reporters.dart';
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
const String skillIsValidMsg = TextReporter.skillIsValidMsg;
@visibleForTesting
const String skillIsInvalidMsg = TextReporter.skillIsInvalidMsg;
@visibleForTesting
const String warningsMsg = TextReporter.warningsMsg;

@visibleForTesting
const String evaluatingDirMsg = TextReporter.evaluatingDirMsg;

@visibleForTesting
const String directoryErrorMsg = TextReporter.directoryErrorMsg;

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
  /// * [format] specifies the output format for diagnostics ([OutputFormat.text], [OutputFormat.json], [OutputFormat.sarif]).
  /// * [reporter] optionally specifies a custom [Reporter] instance.
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
    this.format = OutputFormat.text,
    Reporter? reporter,
  }) : reporter =
           reporter ?? Reporter.fromFormat(format, quiet: quiet, printWarnings: printWarnings),
       resolvedRuleConfigs = _mergeDeprecatedRules(resolvedRules, resolvedRuleConfigs),
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
  final OutputFormat format;
  final Reporter reporter;

  final List<ValidationResult> _results = [];

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

  /// Validates a single skill directory passed via `--skill` / `-s`.
  ///
  /// Returns `true` if the caller should continue iterating, `false` to
  /// stop. Only a real validation failure under [fastFail] returns `false`;
  /// a missing directory contributes to [anyFailed] but still allows the
  /// caller to continue.
  Future<bool> processIndividualSkill(String skillPath) async {
    final String normalizedSkillPath = _ingestPath(skillPath);
    reporter.onDirectoryEvaluating(normalizedSkillPath);
    final skillDir = Directory(normalizedSkillPath);

    if (!skillDir.existsSync()) {
      reporter.onNoSkillsFound('Specified skill directory does not exist: $normalizedSkillPath');
      _results.add(
        ValidationResult(
          validationErrors: [
            ValidationError(
              ruleId: Validator.pathDoesNotExist,
              file: normalizedSkillPath,
              message: 'Specified skill directory does not exist: $normalizedSkillPath',
              severity: AnalysisSeverity.error,
            ),
          ],
        ),
      );
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
    _results.add(finalResult);

    if (generateBaseline) {
      await _saveBaseline(ignorePath, ignores);
    } else {
      final String fullPath = p.absolute(skillDir.path);
      for (final ignore in skillIgnores) {
        if (!ignore.used) {
          reporter.onStaleIgnoreFound(
            ruleId: ignore.ruleId,
            skillName: skillName,
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
  Future<bool> processSkillRoot(String rootPath) async {
    final String normalizedRootPath = _ingestPath(rootPath);
    reporter.onDirectoryEvaluating(normalizedRootPath);
    final rootDir = Directory(normalizedRootPath);

    if (!rootDir.existsSync()) {
      reporter.onNoSkillsFound('Specified root directory does not exist: $normalizedRootPath');
      _results.add(
        ValidationResult(
          validationErrors: [
            ValidationError(
              ruleId: Validator.pathDoesNotExist,
              file: normalizedRootPath,
              message: 'Specified root directory does not exist: $normalizedRootPath',
              severity: AnalysisSeverity.error,
            ),
          ],
        ),
      );
      _anyFailed = true;
      return true;
    }

    List<FileSystemEntity> entities;
    try {
      entities = await rootDir.list().toList();
    } catch (_) {
      reporter.onDirectoryError(
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
          reporter.onStaleIgnoreFound(
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
        reporter.onIndividualSkillHint(message);
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
      reporter.onNoSkillsFound(message);
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
    if (p.isAbsolute(normalized) && _isAtOrWithin(skillPath, normalized)) {
      return p.relative(normalized, from: skillPath);
    }
    return normalized;
  }

  /// Whether the file or directory at path [candidate] is the directory at path
  /// [parent], or sits somewhere under it.
  ///
  /// `p.isWithin` answers `false` when the two paths are equal. An error
  /// reported against the skill directory itself needs the equal case to count,
  /// so that [baselineFileName] reaches `p.relative` and records `.` rather
  /// than an absolute path.
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
    reporter.onSkillEvaluating(skillName);
    final ValidationResult result = await validator.validate(skillDir);
    _applyIgnores(result, skillIgnores, skillDir);
    reporter.onSkillValidationComplete(result);
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
        reporter.onFixFailed(ruleName: rule.name, error: e);
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
      reporter.onFixApplied(oldSkillName);

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

    if (fix) {
      reporter.onDryRunProposed(
        skillName: oldSkillName,
        targetSkillName: nameChangedByFix ? targetSkillName : null,
        originalContent: originalContent,
        currentContent: currentContent,
      );
    }
    return fallbackResult;
  }

  /// Aligns the skill's parent directory name on disk with the frontmatter
  /// [targetSkillName] if the name changed during the fix process.
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
      reporter.onRenameTargetExists(
        oldSkillName: oldSkillName,
        targetSkillName: targetSkillName,
        destinationPath: newDir.path,
      );
      return skillDir;
    }

    try {
      final Directory renamed = await skillDir.rename(newDirPath);
      reporter.onSkillRenamed(oldSkillName, targetSkillName);
      return renamed;
    } catch (e) {
      reporter.onRenameFailed(
        oldSkillName: oldSkillName,
        targetSkillName: targetSkillName,
        error: e,
      );
      return skillDir;
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
      reporter.onBaselineFailed(ignorePath, e);
    }
  }

  /// Emits the formatted validation output (SARIF or JSON) to [sink] (defaults to [stdout]).
  void emitFormattedOutput([StringSink? sink]) {
    if (sink != null) {
      Reporter.fromFormat(format, out: sink).onSessionComplete(_results, customRules: customRules);
    } else {
      reporter.onSessionComplete(_results, customRules: customRules);
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
        return '';
    }
  }

  /// Converts accumulated validation results into a [SarifLog].
  SarifLog toSarif({String? toolVersion}) {
    return SarifSerializer.toSarifLog(
      _results,
      toolVersion: toolVersion,
      checkTypes: RuleRegistry.allChecks,
      customRules: customRules,
    );
  }

  /// Serializes the [toSarif] output to a JSON string.
  String toSarifJson({bool pretty = true, String? toolVersion}) {
    final SarifLog sarif = toSarif(toolVersion: toolVersion);
    final encoder = pretty ? const JsonEncoder.withIndent('  ') : const JsonEncoder();
    return encoder.convert(sarif.toJson());
  }

  /// Serializes the accumulated validation results as a raw JSON array string.
  String toJsonOutput({bool pretty = true}) {
    final List<Map<String, Object?>> jsonList = _results.map((r) => r.toJson()).toList();
    final encoder = pretty ? const JsonEncoder.withIndent('  ') : const JsonEncoder();
    return encoder.convert(jsonList);
  }
}
