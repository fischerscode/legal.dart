# Architecture decisions

## One package, independent layers

`legal.dart` exports immutable inventory/configuration/policy models, the SPDX
AST, scanner, detector, report renderer, and project coordinator. The CLI adapter
uses args CommandRunner and a typed options adapter; it handles streams and exit
codes. Nothing in the domain imports CLI code or writes stdout. `LegalProject`
loads settings and coordinates components. Reports can be evaluated and rendered
repeatedly without I/O or timestamps.

Runtime dependencies are args (BSD-3-Clause), path (BSD-3-Clause), yaml (MIT), and
pub_semver (BSD-3-Clause), maintained in Dart's tools repositories. Dart has no
standard YAML parser or pub-version-constraint parser. The small SPDX grammar is
implemented locally; official identifier data is vendored. No HTTP or build
framework dependency is needed. Developer tools are dev dependencies only.

## Resolved graph and offline evidence

[Pub deps](https://dart.dev/tools/pub/cmd/pub-deps) supplies a useful resolved
JSON graph, and its
[official producer](https://github.com/dart-lang/pub/blob/master/lib/src/command/deps.dart)
exposes directDependencies and devDependencies separately. However, the
[current entrypoint implementation](https://github.com/dart-lang/pub/blob/master/lib/src/entrypoint.dart)
can acquire dependencies while loading a stale graph. The default scanner
therefore reads only local official inputs, with no pub subprocess or network.
`fromResolvedData` remains available to interpret already-captured pub JSON.

[package_config version 2](https://github.com/dart-lang/package_config/blob/master/doc/specification.md)
is the authoritative local URI map. Resolve rootUri relative to its configuration
file rather than reconstructing pub cache paths. The scanner reads dependency
edges from these resolved packages' pubspecs, and versions/source/hosted provenance
from pubspec.lock. Package names and versions are cross-checked. It walks ancestor
directories to locate shared workspace resolution, selects the requested project,
and seeds traversal from its main dependency names; include-dev adds only that
project's dev edges. An encountered workspace member's dev edges are never followed.

A package can be root-dev yet runtime-reachable; lockfile dependency-kind labels
cannot determine reachability. The root is excluded from its own closure and
cycles are visited once. Ignored packages are still traversed. Root/workspace
members obtain their version from their resolved manifests. No SDK-owned libraries
are invented as pub dependencies. Lockfile hosted URLs distinguish custom servers
from pub.dev, and repository/homepage metadata supplements provenance.

Scanning presumes a current pub resolution. Missing config, lock entries, graph
nodes, directories, mismatched identities or versions fail. A newly changed
constraint should be resolved with pub get; this scanner does not implement pub's
constraint solver. Actual files and versions are scanned rather than silently
fetching newer packages. Reads of local path packages reflect their current files,
so scan immediately before a release.

## Recognition and preservation

Detection prefers package-supplied license files, then SPDX metadata. A metadata
claim cannot replace missing distribution text. The detector recognizes common
root-level names and REUSE LICENSES files. NOTICE is always retained and has no
inferred SPDX identity. Multiple license documents imply AND unless the owner
explicitly reclassifies them after review.

Text recognition delegates to the internal matcher in `pana` 0.23.19,
pinned to that exact version. `PanaLicenseAdapter` owns all implementation imports and translates
results into legal's domain types. The SPDX corpus and algorithm come from pana;
Apache appendix and URL variations are no longer custom recognition branches.
Detection is asynchronous. The wrapper uses pana's 0.95 threshold and its
unclaimed-text rejection limits (more than 50% or a run of at least 50 tokens).

Identification does not imply approval: candidate terms are retained while
unexplained text outside covered ranges, unexplained changed text and overlapping
matches create review findings. The familiar reference subset validates known
cosmetic differences only; it never identifies licenses. Original decoded texts
are always preserved. Pana normalizes copyright lines before matching, so its
ranges must be interpreted against the same preprocessed input. Combined token
ranges, rather than individual match offsets, retain optional appendix coverage.
An internal cache is owned by pana; callers should use one corpus per isolate.

Source execution reads pana's local corpus via package resolution. AOT execution
requires an explicitly supplied corpus directory (CLI `--license-data` or the
`LicenseDetector.licenseDataDirectory` constructor option). The compiled CLI
integration test exercises this offline and verifies an actionable error when
the corpus is absent. No matching code or full corpus is copied from pana.

The larger runtime dependency graph is an explicit tradeoff for reuse. Dogfooding
reviews html 0.15.7 with a version-bound MIT expression override: its full terms
match, but the lengthy contributor attribution exceeds pana's matching limits.

Explicit SPDX declarations remain publisher claims, rather than full-text
proofs. Unknown files are never discarded because another file was recognized.
Binary/invalid UTF-8 fails instead of replacing bytes. The renderer copies original
decoded text without normalization or deduplication.

The parser implements SPDX precedence (WITH > AND > OR), grouping, registered IDs,
exceptions and LicenseRef syntax. It rejects unknown registered IDs and invalid
syntax; input length is bounded. Terms with exceptions are separately allowed;
base denials cover exceptions. OR chooses any permitted branch; AND requires all
branches. The immutable AST prevents accidental arbitrary-string policy matching.

## Output completeness and policy are distinct

Generation does not imply policy approval: inventory and check are separate steps.
Unknown evidence blocks normal generation. An explicit draft option marks output
incomplete. Package approval does not invent missing texts; expression overrides
can resolve recognition of existing texts but cannot fill absent/empty documents.
Ignored packages are omitted without dropping their transitive dependencies.
Output filenames and document paths avoid machine-specific cache locations.

## No build_runner builder in v1

The [build Builder contract](https://pub.dev/documentation/build/latest/build/Builder-class.html)
requires declared input/output relationships. A root output can be represented,
but package cache files and a subprocess-derived dependency graph are outside
normal asset invalidation. A hidden write to the project root would be fragile.
The explicit CLI release step is the primary integration. Future generated Dart
embedding can consume `LicenseReport.renderThirdPartyLicenses`; a builder should
consume a tracked inventory asset instead of rescanning externally as a side effect.

## Releases and development experience

[Melos single-package support](https://melos.invertase.dev/configuration/overview)
uses `workspace: []` with `useRootAsPackage: true`; root tags are plain `v…`.
Conventional versioning and package changelog generation stay native. A second
workspace changelog is disabled to avoid writing twice to the same file.
[pub.dev trusted publishing](https://dart.dev/tools/pub/automated-publishing)
uses the official reusable workflow and a separate pre-publication tag validation
job. Actions use major-version tags. No fork PR obtains publish rights.

Repository-quality inspiration: [fischerscode/lti.dart](https://github.com/fischerscode/lti.dart).
This implementation retains a single root package rather than inheriting a
monorepo or Flutter structure.
