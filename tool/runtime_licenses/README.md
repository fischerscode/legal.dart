# Native Dart runtime license catalog

These are original upstream texts, maintained centrally with legal and embedded
in `lib/src/licenses/runtime_data.g.dart`. The source manifest and text files are
maintenance inputs; `.pubignore` excludes `tool/`, and the runtime does not read
these files. This supports offline compiled legal executables without an asset
lookup. The installed SDK's own documents are still read independently.

## Initial scope: Dart 3.13.4 / linux-x64, partial

The catalog is an initial collection of pinned native dependency texts, not a
completed binary inventory. `complete: false` and the manifest's `issues` preserve
that distinction. Compiler runtime components and source-file-specific notices
remain to be audited, including the exact official SDK binary and build flags.
Custom SDK builds, application native assets, and dynamically linked system
libraries are outside this collection's scope. No other target or release is
assumed equivalent.

The selection is based on these official SDK sources:

- [DEPS](https://github.com/dart-lang/sdk/blob/3.13.4/DEPS) pins BoringSSL, ICU,
  zlib, libc++ and libc++abi revisions.
- [runtime/bin/BUILD.gn](https://github.com/dart-lang/sdk/blob/3.13.4/runtime/bin/BUILD.gn)
  declares BoringSSL, ICU, embedded ICU data and zlib in the `dart_executable`
  template used by `dartaotruntime`.
- [runtime/BUILD.gn](https://github.com/dart-lang/sdk/blob/3.13.4/runtime/BUILD.gn)
  includes double-conversion in `libdart`. The
  [double-conversion README](https://github.com/dart-lang/sdk/blob/3.13.4/third_party/double-conversion/README.dart)
  identifies upstream revision `7630f84a10f9428b041d0471e71a562141e9684b`.
- [build/config/BUILDCONFIG.gn](https://github.com/dart-lang/sdk/blob/3.13.4/build/config/BUILDCONFIG.gn)
  and [compiler configuration](https://github.com/dart-lang/sdk/blob/3.13.4/build/config/compiler/BUILD.gn)
  describe the configurable C++ runtime. libc++/libc++abi texts are included
  conservatively while the binary/toolchain audit is incomplete.
- [RegExp README](https://github.com/dart-lang/sdk/blob/3.13.4/runtime/vm/regexp/README.md)
  records V8 revision `254cc758346f10be2a7e22e55d90d4defe9cad74` for the ported
  RegExp implementation. The original V8 LICENSE at that revision is retained.

Each manifest component records the original source URL, document kind and
SHA-256 hash of the original UTF-8 bytes. Retrieved Gitiles TEXT responses were
base64 decoded; the decoded files were retained without line-ending changes.
The entire upstream license file is preserved, including notices about support
or build code that may not be linked into a runtime.

Reviewed classifications are limited to the relevant component terms:

- BoringSSL: Apache-2.0; its LICENSE also preserves the BSD notice for Go test
  support code which explicitly says it is not linked into BoringSSL.
- ICU: `LicenseRef-Dart-runtime-ICU`, because its full file includes Unicode-3.0,
  older ICU terms, data notices and other code/build license notices. This avoids
  presenting the full file as a single permissive license. Approval requires
  review of the original file, not just its first SPDX marker.
- zlib: Zlib; double-conversion and the ported V8 RegExp code: BSD-3-Clause.
- libc++/libc++abi: Apache-2.0 WITH LLVM-exception. Their original files also retain
  the historical MIT/University of Illinois terms and explain the transition.

Runtime component inventory versions are **SDK versions**. Upstream revisions
remain in the pinned source URLs; they are not misrepresented as Pub versions.

## Maintenance

1. Select the exact SDK version, target and runtime build profile being reviewed.
2. Inspect pinned source dependencies, all native/vendor sources, build flags,
   embedded data, toolchain runtime and the release binary. Record audit evidence
   and remaining gaps in the manifest. Never infer coverage from root LICENSEs.
3. Retain complete original license/notice files from the pinned revisions and
   record SHA-256 hashes. Set `kind: notice` only for supplementary notices, not
   to bypass license policy evaluation.
4. Keep `complete: false` while gaps remain. Only after the audit covers the
   declared target/profile may `complete` become true and `issues` become empty.
5. Run `python3 tool/generate_runtime_licenses.py`, format Dart, and run tests.
   Generation verifies hashes and embeds UTF-8 text without fetching or rewriting
   it. Commit both provenance inputs and generated Dart data together.

The catalog supports multiple exact version/target entries; duplicate selections
are rejected. A missing entry never falls back to a neighboring version or host.
SDK coverage is a report-level condition separate from SPDX recognition. Package
ignore/approval rules and manually supplied extra SDK files cannot silently
claim that a partial audit is complete.
