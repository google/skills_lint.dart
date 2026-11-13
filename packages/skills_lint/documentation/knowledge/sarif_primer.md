# SARIF 2.1.0 Integration and Architecture Primer

## Overview

Static Analysis Results Interchange Format (SARIF) is an OASIS standard JSON format for output from static analysis tools. `skills_lint` implements SARIF 2.1.0 compliant output via the `--format=sarif` command-line option, enabling direct ingestion by GitHub Code Scanning, IDE extensions, and continuous integration dashboards.

## Schema Compliance

- **Canonical Schema URI**: `https://docs.oasis-open.org/sarif/sarif/v2.1.0/errata01/os/schemas/sarif-schema-2.1.0.json`
- **Specification Version**: `2.1.0`
- **Tool Driver**:
  - `name`: `skills_lint`
  - `informationUri`: `https://github.com/google/skills_lint.dart`
  - `rules`: Full catalog of registered diagnostic rules with stable identifiers, descriptions, help URIs, and default configuration levels.

## Diagnostic Severity Mapping

`skills_lint` maps internal `AnalysisSeverity` levels to standard SARIF 2.1.0 result levels:

| `AnalysisSeverity` | SARIF Result Level | Ingestion Behavior |
|---|---|---|
| `AnalysisSeverity.error` | `error` | Blocks pull requests, reports failure in GitHub Code Scanning |
| `AnalysisSeverity.warning` | `warning` | Displays advisory notice in code review and scan tabs |
| `AnalysisSeverity.disabled` | `none` | Suppressed from SARIF run results unless explicitly queried |

## Source Location Coordinates

All SARIF locations in `skills_lint` use 1-based coordinates in accordance with SARIF 2.1.0 §3.30.2:
- `startLine`: 1-based line number (minimum value 1).
- `startColumn`: Optional 1-based character column offset.
- `endLine`: Optional 1-based ending line number.
- `endColumn`: Optional 1-based ending character column offset.
- Whole-File Diagnostics: Whole-file violations (such as missing skill files or directory structure failures) default to line 1.

## GitHub Code Scanning Integration

To upload SARIF findings to GitHub Code Scanning, follow the [GitHub Code Scanning recipe](../../README.md#recipe-github-code-scanning-sarif) in the README. This repository runs the same steps in [.github/workflows/code_scanning.yaml](../../../../.github/workflows/code_scanning.yaml).
