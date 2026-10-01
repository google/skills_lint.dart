# Benchmarks

The benchmark measures the compiled CLI as a separate process, the way a user
or a CI step runs it. `validate_1000_skills_all_rules` validates a generated
repository of 1000 skills with every built-in rule on, and records wall time
and peak RSS (the most physical RAM that the process used; Linux and macOS
only). [`src/fixture.dart`](src/fixture.dart) describes the repository.

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

# Time each rule on its own, in process.
dart run benchmark/rule_timings.dart
dart run benchmark/rule_timings.dart --json /tmp/before.json
# ...change the code...
dart run benchmark/rule_timings.dart --baseline-json /tmp/before.json
```

Both scripts print a Markdown report. `--json <path>` and `--markdown <path>`
also write it to files. A benchmark run with a baseline takes under a minute
on a laptop. Close other busy programs while it runs.

In CI, [`benchmarks.yaml`](../../../.github/workflows/benchmarks.yaml)
compares each change with its parent and puts both reports in the job
summary. To compare with another commit, such as a release tag, start the
workflow by hand and enter it as `baseline`. The workflow informs and never
gates. A failed build or run shows as a warning in the job summary.

## Reading the report

The benchmark report lists, for each metric and build, the minimum, median,
90th percentile, maximum and median absolute deviation (MAD) of the timed
runs. Judge by the median. With a baseline, a median change above the
threshold in [`src/report.dart`](src/report.dart) is marked `possible
regression` and adds a warning annotation in CI. When you see one, rerun the
workflow. If the slowdown is still there, compare the two commits locally.

The rule timings report lists, for each rule, its time per skill, its share of
the time of all rules and its MAD. With a baseline, it adds the change, and
marks a rule that the baseline lacks as **new rule**. These timings run the
two builds one after the other, so look only at large changes and new rules.

## Measured noise

A self-comparison (the same checkout as baseline and candidate) shows the
noise. Any change between the two medians is noise.

| Machine | Runs | Wall time median | MAD within a run | Wall time change | Peak RSS change |
| --- | ---: | --- | --- | --- | --- |
| Apple M-series laptop, macOS, 16 logical CPUs | 3 | 395-431 ms | 0.6-5.7% | -0.1%, +0.4%, -5.4% | 0.0% |

The medians of separate CI runs differ by up to 35%, because each run can get
a different runner machine. That is why both builds run in the same job and
the report compares them only with each other.
