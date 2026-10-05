The CLI tests from `test/`, run against a binary built by `dart compile exe`.
A test goes here only as a call to CLI tests in `test/`, so both ways of running the CLI share them.
Run with `dart test compiled_test`. Its setup compiles the binary and fails if compiling fails.
