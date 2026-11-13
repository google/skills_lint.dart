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

To ingest SARIF findings into GitHub Code Scanning, give the job `security-events: write` permission and add these steps:

```yaml
# skills_lint exits non-zero (1 for findings, 78 for configuration errors).
# Standard output writes the SARIF report when validation runs, while standard
# error prints findings, warnings, and errors to this step's log.
- name: Run linter and generate SARIF
  id: lint
  run: dart run skills_lint --format=sarif > results.sarif

# !cancelled() uploads the report on both success and failure while respecting
# workflow cancellation. Skip the upload if setup failed before the lint step
# ran, and on fork pull requests, which lack security-events: write.
- name: Upload SARIF to GitHub Code Scanning
  if: ${{ !cancelled() && steps.lint.conclusion != 'skipped' && (github.event_name != 'pull_request' || !github.event.pull_request.head.repo.fork) }}
  uses: github/codeql-action/upload-sarif@9b3254085494b55a0f7c4c2b3d2d52cc712ce370 # v4.39.1
  with:
    sarif_file: results.sarif
    category: skills_lint
```

> Note: When the linter finds violations, the lint step fails the job while `!cancelled()` still lets the upload step publish the SARIF report to Code Scanning. This repository runs these steps in [.github/workflows/code_scanning.yaml](../../../../.github/workflows/code_scanning.yaml).
