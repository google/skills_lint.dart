# Third-Party Vendored Agent Skills

This directory (`third_party/skill-repos/`) vendors external agent skills from remote repositories for use during development of `skills_lint`.

## Directory Structure

Each remote repository is vendored into its own subdirectory following this structure:

```
third_party/skill-repos/
├── <repo-slug>/
│   ├── LICENSE                                # Upstream repository license
│   ├── .config/dart_skills/skills_config.json # Dart skills configuration
│   └── .agents/skills/                        # Vendored skill directories
│       └── <skill-name>/
│           └── SKILL.md
```

Skills vendored here are symlinked into `packages/skills_lint/.agents/skills/` so agents working on the package can access them directly without additional setup.

## Managing Vendored Skills

All skill operations use the official Dart `skills` package (`dart install skills@^1.0.0`).

### Adding a New Skill from an Existing Vendored Repository

1. Navigate to the target repository directory:
   ```bash
   cd third_party/skill-repos/<repo-slug>
   ```

2. Ensure the remote repository's `LICENSE` file is present and up-to-date in this directory.

3. Add the skill using `skills add`:
   ```bash
   skills add <remote-repo> --skill <skill-name> --agent generic
   ```

4. Create a relative symlink from `packages/skills_lint/.agents/skills/`:
   ```bash
   cd ../../packages/skills_lint/.agents/skills
   ln -s ../../../../third_party/skill-repos/<repo-slug>/.agents/skills/<skill-name> <skill-name>
   ```

5. Validate the newly linked skill using the repository linter and test suite:
   ```bash
   cd ../..
   dart test test/skills_lint_skills_test.dart
   ```

6. Stage and commit the vendored files, updated `.config/dart_skills/skills_config.json`, and the new symlink.

### Adding Skills from a New Remote Repository

1. Create the new vendor directory under `third_party/skill-repos/`:
   ```bash
   mkdir -p third_party/skill-repos/<new-repo-slug>
   cd third_party/skill-repos/<new-repo-slug>
   ```

2. Copy the remote repository's `LICENSE` file into the new directory.

3. Install the desired skill(s):
   ```bash
   skills add <remote-repo> --skill <skill-name> --agent generic
   ```

4. Create relative symlink(s) in `packages/skills_lint/.agents/skills/`:
   ```bash
   cd ../../packages/skills_lint/.agents/skills
   ln -s ../../../../third_party/skill-repos/<new-repo-slug>/.agents/skills/<skill-name> <skill-name>
   ```

5. Stage and commit all newly added files and symlinks.

### Updating Existing Vendored Skills

To roll or update an existing skill to the latest upstream version:

1. Navigate to the vendor repository directory:
   ```bash
   cd third_party/skill-repos/<repo-slug>
   ```

2. Re-run `skills add`:
   ```bash
   skills add <remote-repo> --skill <skill-name> --agent generic
   ```

3. Verify the diff in `.agents/skills/<skill-name>/` and `.config/dart_skills/skills_config.json`.

4. Run the skills validation test in `packages/skills_lint`:
   ```bash
   cd ../../packages/skills_lint
   dart test test/skills_lint_skills_test.dart
   ```
   *(This test executes `skills_lint` against all configured directories in `skills_lint.yaml`, including `.agents/skills` and its symlinked third-party skills).*

5. Stage and commit the updated vendored skill files and configuration.
