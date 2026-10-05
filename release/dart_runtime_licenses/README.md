# Dart runtime licenses

`dart compile exe` links the Dart runtime into every executable, and the
runtime contains third-party code. The Dart SDK's own `LICENSE` file doesn't
cover that code, so `release/lib/src/licenses.dart` adds these license texts to
the `LICENSE` file in each release archive.

| File | Component | Source |
| :--- | :--- | :--- |
| `boringssl.txt` | BoringSSL, for `dart:io` TLS | [boringssl `LICENSE`](https://boringssl.googlesource.com/boringssl/+/2e508c973d634b3aa51b71db5062bc6b096e5031/LICENSE) |
| `double-conversion.txt` | double-conversion, for number formatting | [dart-lang/sdk `third_party/double-conversion/LICENSE`](https://github.com/dart-lang/sdk/blob/04bcd1036cdc799ac6564988f159ee454d42c822/third_party/double-conversion/LICENSE) |
| `icu.txt` | ICU and its embedded data | [chromium/deps/icu `LICENSE`](https://chromium.googlesource.com/chromium/deps/icu/+/a86a32e67b8d1384b33f8fa48c83a6079b86f8cd/LICENSE) |
| `perfetto.txt` | Perfetto protozero, for timeline tracing | [google/perfetto `LICENSE`](https://github.com/google/perfetto/blob/13ce0c9e13b0940d2476cd0cff2301708a9a2e2b/LICENSE) |
| `zlib.txt` | zlib, for `dart:io` compression | [chromium zlib `LICENSE`](https://chromium.googlesource.com/chromium/src/third_party/zlib/+/3008c4b3a06bd65392c31db8846000a21e3d03c5/LICENSE) |

The revisions are the ones that the
[`DEPS` file](https://github.com/dart-lang/sdk/blob/04bcd1036cdc799ac6564988f159ee454d42c822/DEPS)
of Dart 3.13.5 pins. The runtime's dependencies on these components are in
[`runtime/bin/BUILD.gn`](https://github.com/dart-lang/sdk/blob/04bcd1036cdc799ac6564988f159ee454d42c822/runtime/bin/BUILD.gn)
and
[`runtime/BUILD.gn`](https://github.com/dart-lang/sdk/blob/04bcd1036cdc799ac6564988f159ee454d42c822/runtime/BUILD.gn).

## Why the archives include them

The Dart SDK's `LICENSE` covers only the Dart project's own code. The Dart team
[removed the third-party licenses from it](https://github.com/dart-lang/sdk/commit/c6511027931ad2384441e4b0db6c3fdd22371e4b)
because each `third_party` folder of the SDK source holds its own license. The
SDK download has no `third_party` folder. Each license states what a binary
distribution must carry:

- BoringSSL and Perfetto: Apache License 2.0, section 4(a), "You must give any
  other recipients of the Work or Derivative Works a copy of this License".
- double-conversion: the BSD 3-clause license, "Redistributions in binary form
  must reproduce the above copyright notice, this list of conditions and the
  following disclaimer in the documentation and/or other materials provided
  with the distribution."
- ICU: the Unicode license, which requires that "this copyright and permission
  notice appear with all copies of the Data Files or Software" or in
  associated documentation.
- zlib: the zlib license requires its notice in source distributions only.
  The archives include it to credit the code.

## Updating

Check these files when the release workflow moves to a new Dart SDK:

1. Find the SDK's revision in the `revision` file of the SDK, or in
   `https://storage.googleapis.com/dart-archive/channels/stable/release/<version>/VERSION`.
2. Read `boringssl_rev`, `icu_rev`, `perfetto_rev` and `zlib_rev` from `DEPS`
   at that revision.
3. Download each `LICENSE` at its revision. The googlesource pages return the
   file base64-encoded when you add `?format=TEXT` to the URL.
4. If `runtime/BUILD.gn` or `runtime/bin/BUILD.gn` link another third-party
   library, add its license here and to `dartRuntimeLicenseFiles` in
   `release/lib/src/licenses.dart`.
