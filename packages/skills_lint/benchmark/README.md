# Performance Benchmarks (`bench_press`)

This directory contains multi-runtime benchmarks powered by [`bench_press`](https://pub.dev/packages/bench_press).

## Running Benchmarks

### 1. Fast Smoke-Test Validation (~1-2s)

Verifies syntax, builds, and runtime execution across target compilers:

```bash
# Validate default target (JIT)
dart run bench_press validate benchmark/

# Validate across JIT and Native AOT
dart run bench_press validate -t jit,aot benchmark/
```

### 2. Full Benchmark Suite

Runs steady-state calibrated benchmarks with statistical confidence intervals:

```bash
# Run on JIT
dart run bench_press run benchmark/

# Run across multiple runtimes
dart run bench_press run -t jit,aot benchmark/
```

### 3. Comparing Against Baselines (`--diff`)

```bash
# Diff against main branch
dart run bench_press run --diff origin/main benchmark/

# Save a baseline JSON file
dart run bench_press run --save baseline.json benchmark/

# Diff against saved baseline
dart run bench_press run --diff baseline.json benchmark/
```

