# Benchmarks

These benchmarks track the performance that a `skills_lint` user notices:
how long the CLI takes, and how much memory it uses, on repositories of
skills. They run the compiled CLI as a separate process, the same way a
user, a pre-commit hook or a CI step runs it.

## What is measured

| Benchmark | Metric | User workflow |
| --- | --- | --- |
| `large_repo_aot` | wall time | The installed executable (`dart install skills_lint` or a release binary) validating a repository of 1000 skills. |
| `large_repo_aot` | peak RSS | Memory use of the same runs. Linux and macOS only. |
| `small_repo_jit` | wall time | `dart run skills_lint` on a repository of 5 skills, as in a pre-commit hook. Startup dominates this time. |

The runner generates both repositories from a fixed seed, so every run
validates the same files. Each skill has a `SKILL.md` with varied optional
frontmatter fields and Markdown links to files under `references/` and
`scripts/`. One skill in ten has one lint error, rotating through a name
mismatch, trailing whitespace, a broken relative link, a description over
1024 characters and an absolute link. A `skills_lint.yaml` at the root turns
on every rule that needs no extra context. The 1000-skill repository has
about 3400 files and 10 MB of text.

The CLI builds for the two runtimes the way users get them:
`dart compile exe` for the installed executable, and
`dart compile kernel --no-link-platform` for `dart run`, which runs the same
kind of kernel file from a dependent package.

A slowdown of one of these is worth a person's time to investigate. Other
paths are left out because they add run time and noise without covering
much that these do not:

- `--generate-baseline` on the large repository takes the same time as a
  plain run.
- `--fix` on the large repository adds file writes for the few fixable
  skills. Users run it rarely and interactively, and a slowdown in
  validation also shows in `large_repo_aot`.
- The in-process `validateSkills` API skips process startup and output,
  which users always pay for.

## Running locally

From `packages/skills_lint`:

```bash
# Measure this checkout.
dart run benchmark/run_benchmarks.dart

# Compare this checkout (the candidate) with another checkout (the baseline).
git worktree add ../../../skills_lint_baseline origin/main
(cd ../../../skills_lint_baseline && dart pub get)
dart run benchmark/run_benchmarks.dart --baseline ../../../skills_lint_baseline/packages/skills_lint

# Measure the noise on your machine: compare this checkout with itself.
dart run benchmark/run_benchmarks.dart --baseline .
```

The runner compiles each checkout, generates the repositories in a
temporary directory, runs the benchmarks and prints a Markdown report to
standard output. `--json <path>` and `--markdown <path>` also write the
report to files. A full run with a baseline takes under a minute on a
laptop. Close other busy programs while it runs.

## Running in CI

[`.github/workflows/benchmarks.yaml`](../../../.github/workflows/benchmarks.yaml)
runs on pull requests and pushes to `main` that change the CLI code
(`bin/`, `lib/`, `pubspec.yaml`) or the benchmarks. It compares the change
with its parent: on a pull request, the tip of the base branch; on a push,
the previous commit on `main`. To compare against another commit, such as
the latest release tag, start the workflow by hand from the Actions tab and
enter the commit, branch or tag as `baseline`. This shows slow drift that no
single commit causes.

The results are in the job summary, and the JSON and Markdown reports are
in the `benchmarks` artifact of the run.

The workflow never fails because of a slowdown. It fails only if the CLI
does not build or does not report the expected lint failure on a generated
repository, because then the timings would be meaningless.

## Reading the report

For each benchmark, metric and build, the report lists the number of timed
runs and their minimum, median, 90th percentile, maximum and median
absolute deviation (MAD). Judge by the median: a few runs slowed by other
work on the machine do not move it. MAD, also shown as a percentage of the
median, shows how much the runs spread.

With a baseline, the report also compares the medians. A change above the
threshold is marked `possible regression`, and in CI it adds a warning
annotation to the run. When you see one:

1. Rerun the workflow. If the second run does not show the slowdown, it was
   noise.
2. If it does, compare the two commits locally and look for the change that
   caused it.

## Why the runs are not flaky

- Each baseline run and candidate run happens in the same job on the same
  machine, and the builds take turns (A B, B A, A B, ...). A slower machine
  or a busy neighbour affects both builds alike, so the comparison stays
  valid even when absolute times vary between runners.
- Every benchmark has fixed warmup and timed run counts. Warmup runs fill
  the file cache and page in the executable.
- The report uses medians, not means.
- No benchmark has an absolute time limit.

## Measured noise

To set the thresholds, the runner compared a build with itself
(`--baseline .`). Any difference between the two medians is noise.

| Machine | Runs | `large_repo_aot` wall time | `large_repo_aot` peak RSS | `small_repo_jit` wall time |
| --- | ---: | --- | --- | --- |
| Apple M-series laptop, macOS, 16 logical CPUs | 6 | median 528-559 ms, largest change 1.3% | 70.0 MiB, largest change 0.0% | median 115-120 ms, largest change 3.0% |

The thresholds in [`src/report.dart`](src/report.dart) are 25% for wall
time and 10% for peak RSS, several times the largest noise seen.

## Changing a benchmark

Each benchmark name stands for one workload. If you change a benchmark's
fixture, runtime or run counts, rename it, so that stored results under one
name always come from one workload. The comparison
within one run is always valid, because both builds run the same workload.
