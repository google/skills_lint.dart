# Developer & Agent Guide: Agent Skills Linter (`skills_lint`)

This repository houses `skills_lint`, a static analysis linter and remediation tool for AI Agent Skills (`SKILL.md`) written in Dart.

## 📚 Knowledge & Documentation Links

Before making changes or implementing features, consult the following knowledge resources:

- [Architecture Overview](packages/skills_lint/documentation/knowledge/architecture_overview.md): System boundaries, execution lifecycle, and durable architectural patterns.
- [Style Guide](packages/skills_lint/documentation/knowledge/style_guide.md): Effective Dart conventions, documentation standards, class constants, and diagnostic formatting.
- [SARIF Primer](packages/skills_lint/documentation/knowledge/sarif_primer.md): OASIS SARIF 2.1.0 document model, GitHub Code Scanning integration, and severity mappings.

---

## ✅ Definition of Done Checklist

Every pull request and modification must satisfy the following checks before landing:

1. **Formatting:** `dart format --output=none --set-exit-if-changed .` passes with zero modifications.
2. **Analysis:** `dart analyze --fatal-infos` passes cleanly across the entire workspace with zero warnings, errors, or info lints.
3. **Tests:** `dart test` passes 100% across all unit and integration test suites in `packages/skills_lint`.
4. **Cognitive Complexity:** `dart run cognitive_complexity --fail-threshold 20 packages/skills_lint/bin packages/skills_lint/lib packages/skills_lint/test packages/skills_lint/example packages/skills_lint/skills .agents/skills` passes with zero violations.
5. **Effective Dart & Style:** All new code complies with the [Style Guide](packages/skills_lint/documentation/knowledge/style_guide.md).
6. **Authentication & Commits:** Pushes to GitHub must authenticate via HTTPS using the configured agent credentials (`reidbaker-agent`), never falling back to personal SSH keys.
