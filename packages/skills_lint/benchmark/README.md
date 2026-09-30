# Benchmarks

This benchmark tracks the performance that a `skills_lint` user notices:
how long the CLI takes, and how much memory it uses, on a large repository
of skills. It runs the compiled CLI as a separate process, the same way a
user or a CI step runs it.

## What is measured

One benchmark, `validate_1000_skills_all_rules`, records two metrics:

| Metric | What it covers |
| --- | --- |
| wall time | The installed executable (`dart install skills_lint` or a release binary) validating a repository of 1000 skills with every built-in rule on. |
| peak RSS | Memory use of the same runs. Linux and macOS only. |

The runner builds the CLI with `dart compile exe` and generates the
repository from a fixed seed, so every run validates the same files. Each
skill has a `SKILL.md` with varied optional frontmatter fields and Markdown
links to files under `references/` and `scripts/`. One skill in ten has one
lint error, rotating through a name mismatch, trailing whitespace, a broken
relative link, a description over 1024 characters and an absolute link. The
repository has about 3400 files and 10 MB of text.

### Why every rule is on

A `skills_lint.yaml` at the fixture root turns on every built-in rule, not
only the rules that are on by default. Most of the rule time is in rules
that are off by default, so a benchmark with only the default rules would
miss a slowdown in them. On the 1000-skill fixture (Apple M-series laptop,
15 timed runs per configuration, medians):

| Rules on | Wall time | Added by rules |
| --- | ---: | ---: |
| None | 238 ms | |
| Default rules | 312 ms | 75 ms |
| Every rule | 553 ms | 315 ms |

`check-trailing-whitespace` (141 ms), `check-relative-paths` (61 ms) and
`published-skill-name` (17 ms) are off by default and add about 70% of the
rule time. `check-absolute-paths` (50 ms) is the costliest default rule.
The default rules are a subset of every rule, so a slowdown in a default
rule also shows in this benchmark.

### What is left out

A slowdown in this benchmark is worth a person's time to investigate. Other
paths are left out because they add run time and noise without covering
much that it does not:

- `--generate-baseline` on the large repository takes the same time as a
  plain run.
- `--fix` on the large repository adds file writes for the few fixable
  skills. Users run it rarely and interactively, and a slowdown in
  validation also shows here.
- A small repository takes about 10 ms with the installed executable. Under
  `dart run`, the Dart VM startup dominates its time, and a slowdown in
  `skills_lint` code also shows in the large repository.
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

The runner compiles each checkout, generates the repository in a temporary
directory, runs the benchmark and prints a Markdown report to standard
output. `--json <path>` and `--markdown <path>` also write the report to
files. A run with a baseline takes under a minute on a laptop. Close other
busy programs while it runs.

## Running in CI

[`.github/workflows/benchmarks.yaml`](../../../.github/workflows/benchmarks.yaml)
runs on pull requests and pushes to `main` that change the CLI code
(`bin/`, `lib/`, `pubspec.yaml`) or the benchmark. It compares the change
with its parent: on a pull request, the tip of the base branch; on a push,
the previous commit on `main`. To compare against another commit, such as
the latest release tag, start the workflow by hand from the Actions tab and
enter the commit, branch or tag as `baseline`. This shows slow drift that no
single commit causes.

The results are in the job summary, and the JSON and Markdown reports are
in the `benchmarks` artifact of the run.

The workflow never fails because of a slowdown. It fails only if the CLI
does not build or does not report the expected lint failure on the
generated repository, because then the timings would be meaningless.

## Reading the report

For each metric and build, the report lists the number of timed runs and
their minimum, median, 90th percentile, maximum and median absolute
deviation (MAD). Judge by the median: a few runs slowed by other work on
the machine do not move it. MAD, also shown as a percentage of the median,
shows how much the runs spread.

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
- The benchmark has fixed warmup and timed run counts. Warmup runs fill the
  file cache and page in the executable.
- The report uses medians, not means.
- No benchmark has an absolute time limit.

## Measured noise

To set the thresholds, the runner compared a build with itself. Any
difference between the two medians is noise.

| Machine | Runs | Wall time: median, MAD within a run | Wall time: largest change | Peak RSS: largest change |
| --- | ---: | --- | ---: | ---: |
| Apple M-series laptop, macOS, 16 logical CPUs | 5 | 530-541 ms, MAD 0.6-2.2% | 0.8% | 0.1% |
| GitHub `ubuntu-latest`, 4 logical CPUs | 6 | 613-825 ms, MAD 0.5-2.1% | 0.8% | 0.1% |

The medians of separate CI runs differ by up to 35%, because each run can
get a different runner machine. That is why both builds run in the same job
and the report compares them only with each other.

The warning thresholds in [`src/report.dart`](src/report.dart) are 15% for
wall time and 10% for peak RSS: more than ten times the largest noise
seen. At 15%, doubling the cost of the costliest rule,
`check-trailing-whitespace` (about 25% of the run), crosses the threshold.
Doubling a cheaper rule does not, so per-rule costs need a separate report.

## Changing a benchmark

Each benchmark name stands for one workload. If you change a benchmark's
fixture, rules or run counts, rename it, so that stored results under one
name always come from one workload. The comparison within one run is always
valid, because both builds run the same workload.
