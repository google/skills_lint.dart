# write

Encapsulates all file writes, baseline persistence, and write-confinement checks
for `--fix`, `--generate-baseline`, and missing-ignore-file initialization:

- `WriteBoundary`: resolves symlinks (including dangling links and `..` after a
  link) and checks that every written or renamed path stays inside the scanned
  directory or an explicitly allowed directory (`write_allow` / `--allow-write`).
- `SkillWriter`: executes `--fix` directory renames and `SKILL.md` writes behind
  preflight and boundary checks, undoing a rename if writing `SKILL.md` fails.
- `IgnoreFileTarget`, `IgnoreFileWriter`, and `SkillsIgnoresStorage`: resolve,
  parse, initialize, and save baseline/ignore files while enforcing every
  sharing target's `WriteBoundary`.
