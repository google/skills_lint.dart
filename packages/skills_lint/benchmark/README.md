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
only the rules that are on by default. Much of the rule time is in rules
that are off by default, so a benchmark with only the default rules would
miss a slowdown in them. On the 1000-skill fixture (Apple M-series laptop,
15 timed runs per configuration, medians, MAD 4-9%):

| Rules on | Wall time | Added by rules |
| --- | ---: | ---: |
| None | 259 ms | |
| Default rules | 325 ms | 67 ms |
| Every rule | 423 ms | 165 ms |

`check-relative-paths` (79 ms) is off by default and is the costliest
rule. `check-absolute-paths` (55 ms) is the costliest default rule. The
rules that are off by default add about 60% of the rule time. The default
rules are a subset of every rule, so a slowdown in a default rule also
shows in this benchmark. `test/benchmark/timings_test.dart` fails if a
registered rule is missing from the fixture's `skills_lint.yaml`.

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

These runs used the CLI at commit `6c26254`, whose all-rules run took
about 540 ms locally.

The medians of separate CI runs differ by up to 35%, because each run can
get a different runner machine. That is why both builds run in the same job
and the report compares them only with each other.

The warning thresholds in [`src/report.dart`](src/report.dart) are 15% for
wall time and 10% for peak RSS: more than ten times the largest noise
seen. The threshold catches broad slowdowns, such as slower file reading
or parsing, or a rule that gets several times slower. A new rule, or a
slowdown in one cheap rule, usually adds less than 15% of the run, so the
benchmark does not warn about it. The rule timings below show it instead.

## Rule timings

[`rule_timings.dart`](rule_timings.dart) times each rule on its own, in
process, through the public `Validator` and `SkillRule` API. It reads and
parses each skill once, then runs one rule at a time over the parsed skills
and reports the median time per skill. It runs on two corpora:

- `fixture`: the benchmark's 1000 generated skills.
- `real`: the skills in `third_party/skill-repos`, `.agents/skills` and
  `packages/skills_lint/skills`.

It turns on the same rules as the benchmark, from the fixture's
`skills_lint.yaml`.

From `packages/skills_lint`:

```bash
# Time this checkout.
dart run benchmark/rule_timings.dart

# Compare with another build: write its timings, then pass them in.
dart run benchmark/rule_timings.dart --json /tmp/before.json
# ...change the code...
dart run benchmark/rule_timings.dart --baseline-json /tmp/before.json
```

For stable numbers, compile the script first
(`dart compile exe benchmark/rule_timings.dart`), as CI does.

For each rule, the report shows whether it is on by default, its time per
skill, its share of the time of all rules, and the MAD. With a baseline, it
also shows the baseline time and the change. A rule that the baseline
doesn't have is marked **new rule**, so a costly new rule stands out even
when the benchmark doesn't warn.

The benchmarks workflow runs the timings on the candidate and, with this
checkout's script, on the baseline, and adds the report to the job summary.
The timings are information only: they have no thresholds and never fail
the job. The two builds run one after the other, not in turns, so small
changes are noise. In local runs, rules whose code didn't change moved by
up to 10%. Look into a change only if it is large, or if a rule is new.

A rule time here leaves out reading the files and starting the process, so
it is smaller than the rule's cost in the benchmark. The rules rank in
about the same order as in the benchmark.

## Changing a benchmark

Each benchmark name stands for one workload. If you change a benchmark's
fixture, rules or run counts, rename it, so that stored results under one
name always come from one workload. The comparison within one run is always
valid, because both builds run the same workload.
