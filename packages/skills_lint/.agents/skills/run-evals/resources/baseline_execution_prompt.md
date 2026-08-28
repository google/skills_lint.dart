Execute this task:
- Task: <eval prompt>
- Input files: <eval files if any, or "none">

WARNING: You are executing in an isolated evaluation environment (branch workspace or worktree). Confine all file modifications strictly to your assigned target working directory. Do NOT use absolute paths to modify files outside your assigned environment.

Once you are done, do not commit. Just send me a message with the `git diff` of your changes, and the output of running verification commands (e.g., `dart pub get`, `dart format`, `dart analyze`, `dart test`).
CRITICAL: You must explicitly `cd` into the `<target-package-root>` directory (or `<worktree-target-package-root>`) before running any verification commands to avoid analyzing unrelated packages in the workspace!
NOTE: If your task is strictly to grade, review, or evaluate code, do NOT fix the issues you find. Leave the code exactly as it is, even if verification commands fail. Your job is only to report the evaluation results.
