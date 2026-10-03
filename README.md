# legal

[![CI](https://github.com/fischerscode/legal.dart/actions/workflows/ci.yml/badge.svg)](https://github.com/fischerscode/legal.dart/actions/workflows/ci.yml)

Inventory the licenses of a Dart application's direct and transitive dependencies,
check a project policy, and generate a deterministic `THIRD_PARTY_LICENSES.txt`
containing the original license and notice texts. Designed for CLI and server
applications distributed as binaries, including `dart compile exe`.

`legal` is a Pure Dart package. Its API is independent of terminal output. Scans
use local resolved packages; no license lookup service or pub.dev API is used.
A dependency inventory describes the resolved package closure, not which code a
compiler's tree shaker retains.

**This tool evaluates your policy, not legal suitability. It is not legal advice.**
Review your release's obligations, notices, source-distribution requirements, and
other bundled software separately.

## Installation and quick start

Requires Dart 3.13 or later. Install the current version as a development dependency:

```sh
dart pub add --dev legal
```

This writes a version constraint to your pubspec. Add your project policy there:

```yaml
legal:
  policy: permissive
  unknown: deny
```

```sh
dart run legal list
dart run legal check
dart run legal generate
```

The output is `THIRD_PARTY_LICENSES.txt`. Include this file with the distributed
binary. Keeping `legal` in `dev_dependencies` excludes the tool itself from your
application's runtime inventory, unless it is also reachable through runtime
imports/declarations. The default scan excludes the root application itself.

For a globally installed executable:

```sh
dart pub global activate legal
legal check --project /path/to/application
legal generate --project /path/to/application
```

Until the initial publication, use this checkout with `dart pub global activate
--source path .` or run `dart run bin/legal.dart` inside it.

## Commands

```sh
dart run legal list --json
dart run legal check --json
dart run legal generate --output dist/THIRD_PARTY_LICENSES.txt
dart run legal generate --force
dart run legal list --include-dev
dart run legal check --project ../app --config legal.yaml
dart run legal generate --help
```

`--project`, `--config`, and `--[no-]include-dev` are command options;
place them after `list`, `check`, or `generate`. Relative config and output paths
are resolved against the selected project. Without `--config`, only the
`legal` mapping in `pubspec.yaml` is used. An explicit `legal.yaml` contains the
same mapping **without** the outer `legal:` key and replaces the pubspec settings;
there is no implicit discovery or merge. `--no-include-dev` overrides configuration.

- `list`: human-readable inventory and policy decisions without enforcing them.
- `check`: the same inventory, returning failure if any policy decision fails.
- `generate`: original texts, stable package/document ordering, no timestamps and
  no deduplication. Generation is independent of allow/deny evaluation: run
  `check` as well before a release.

If the output already exists, `generate` asks for confirmation in a terminal
(`y` or `yes`; the default is no). Without interactive input and output, it fails
with exit code `2` and leaves the existing file unchanged. Use `--force` to
overwrite without prompting, for example in CI or release scripts. This rule
applies to every existing output path; there is no special filename blocklist.

When upgrading from 0.1.x, add `--force` to scripts that regenerate an existing
notice file. Earlier versions overwrote these files without confirmation.

`list --json` and `check --json` emit schema version 1: resolved identity, source,
SPDX expressions, original document text and relative paths, issues, and policy
findings. Ignored packages remain visible in the inventory with status `ignored`.
No ANSI colors are emitted, making redirected and CI output predictable.
`--verbose` includes a stack trace for unexpected errors.

| Exit code | Meaning |
| --- | --- |
| `0` | Command succeeded; check has no failing decisions |
| `1` | Check has at least one policy failure |
| `2` | Scan/configuration/I/O error, incomplete generation, or overwrite refused |
| `64` | Invalid command or arguments |

Generation refuses unresolved evidence or missing/empty license texts. A
manually reviewed `expression` override can resolve recognition of an existing
text; it cannot create missing text. `--allow-incomplete` produces a conspicuously
marked **INCOMPLETE DRAFT** for manual work. A package-level approval does not
waive the generator's completeness checks. Outputs never paraphrase licenses.

## Policy configuration

```yaml
legal:
  output: THIRD_PARTY_LICENSES.txt
  include_dev: false
  policy: permissive
  unknown: deny
  licenses:
    allow:
      - MPL-2.0
    deny:
      - AGPL-3.0-only
  packages:
    ignore:
      - my_internal_package
    overrides:
      reviewed_package:
        versions: '>=1.2.0 <2.0.0'
        licenses:
          allow:
            - MPL-2.0
        reason: 'Reviewed for this distribution in #123'
      special_package:
        versions: '^1.0.0'
        allow: true
        reason: 'Package and notices reviewed in #456'
      custom_license_package:
        expression: MIT
        reason: 'Confirmed the supplied custom-formatted LICENSE is MIT in #789'
```

Without `policy`, the allowlist starts **empty**. `policy: permissive` adds exactly
`MIT`, `BSD-2-Clause`, `BSD-3-Clause`, `Apache-2.0`, and `ISC`. It is a convenience
allowlist, not a legal assurance. Additional `licenses.allow` entries extend it.
Recognized but unlisted terms fail with `requiresReview`. IDs are case sensitive.
Typos, unsupported fields, malformed SPDX syntax, and invalid version constraints
produce contextual errors instead of silently weakening a policy.

`unknown` controls absent, unrecognized, or incomplete license evidence:

- `deny` (default): `requiresReview`, failing check.
- `warn`: `requiresReview`, warning without failing check.
- `allow`: explicitly permitted unresolved evidence.

This setting does not grant approval to a recognized, unlisted license. An
explicitly denied recognized term remains denied even if other evidence is
unknown. Review and generation have separate responsibilities.

### SPDX expressions and precedence

The parser recognizes registered SPDX license IDs and exceptions, `LicenseRef-*`,
optional `DocumentRef-*:LicenseRef-*`, parentheses, `WITH`, `AND`, and `OR`.
The bundled registry is SPDX License List 3.29.0; scans do not fetch updates.
Legacy `GPL-2.0+` is canonicalized to `GPL-2.0-or-later`. Other deprecated IDs
are accepted as their registered spelling; `only` and `or-later` are distinct
policy terms. `LicenseRef` terms require explicit policy approval.

`AND` binds more tightly than `OR`. Every `AND` operand must be allowed; any
allowed `OR` alternative is sufficient. With MIT allowed and GPL-3.0-only denied:

| Expression | Outcome |
| --- | --- |
| `MIT OR GPL-3.0-only` | allowed (MIT alternative) |
| `MIT AND GPL-3.0-only` | denied |
| `MIT AND MPL-2.0` | requires review if MPL is unlisted |
| `GPL-3.0-only OR MPL-2.0` | requires review if MPL is unlisted |

An OR expression is denied only if **all** alternatives are denied. A deny on an
unused OR alternative does not prohibit choosing an allowed alternative.

Global deny takes precedence over global allow **for the same term**. `WITH`
expressions require approval of the complete term, for example
`GPL-2.0-only WITH Classpath-exception-2.0`; approval of the base ID alone does not
approve an exception. Denying a base ID also denies its WITH variants. The
allow/deny lists contain individual terms, not compound AND/OR expressions.

### Package exceptions

The priority order is `ignore`, applicable package exception, global deny,
global allow, and review. Overrides require a nonempty `reason`:

- `packages.ignore` excludes that package from checks and generated notices. Its
  dependencies are still traversed; ignoring your package does not hide its
  third-party dependencies.
- Override `allow: true` explicitly approves that package, including unknown
  evidence and global deny. It remains in the generated notices.
- Override `licenses.allow` approves specific terms for that package, including
  terms globally denied. Other expression operands still need approval.
- Override `expression` supplies a manually reviewed SPDX classification. It
  preserves original documents and evaluates the replacement against policy;
  it is not itself an approval. The rendered notice labels the review reason.
- Optional `versions` uses pub version-constraint syntax. An exception outside
  its range has no effect; it does not approve future major versions implicitly.

## Local evidence and limits

The scanner reads `.dart_tool/package_config.json` for resolved package locations,
`pubspec.lock` for versions/source/provenance, and the actual local package
manifests for dependency edges. It follows only the selected root's runtime
edges, optionally adding that root's dev edges. It never follows another
package's dev dependencies. URI resolution supports path, Git, and symlink
packages, including shared workspace resolution. Versions and package identities
are cross-checked; missing nodes and mismatches fail with a request to run
`dart pub get`. Scans do not invoke pub or change resolution. After resolution,
even a compiled `legal` executable scans without a Dart subprocess. Changed
constraints require a new pub get; the scanner is not a dependency solver.

The detector reads root-level `LICENSE`, `LICENCE`, `COPYING`, and `NOTICE`,
including dotted, underscore, or hyphen suffixes and case variants. It also reads
files directly inside `LICENSES/`. NOTICE is preserved as supplementary evidence,
not interpreted as another license. Multiple license documents are conservatively
combined with **AND**; the tool does not assume dual licensing from filenames.
Use a reasoned `expression` override after reviewing an actual OR arrangement.

Recognition uses explicit `SPDX-License-Identifier:` declarations or the
SPDX text corpus and token matcher shipped with **pana 0.23.18–0.23.19**.
The constraint `>=0.23.18 <0.23.20` allows these two verified versions; newer
versions require an explicit compatibility review because the adapter uses an
internal API.
The internal pana API is isolated behind an adapter; the normal scan remains
local and offline after `dart pub get`. This intentionally brings pana's runtime
dependency tree, including analyzer and test tooling, into legal's dependencies.

The matcher uses pana's 0.95 similarity threshold and rejects candidates with
more than 50% unclaimed tokens or an unclaimed run of at least 50 tokens.
Similarity is a recognition heuristic, not a legal assurance. Candidate SPDX
terms remain separate from review findings: unexplained text outside matches,
overlapping matches, and changed text require review. Known cosmetic variants
of the original common-license references are accepted. Multiple non-overlapping
license texts in one file imply **AND**, without inferring a dual-license choice.
Normal Apache variants, including an omitted appendix or HTTPS URLs, are handled
by pana rather than package-specific recognition rules.

Explicit SPDX declarations are publisher evidence, not proof that a document is
a complete or unmodified standard license. A valid pubspec `license` declaration
is retained as a fallback but missing license text still requires review.
SPDX-ID-only documents likewise require review. The pinned corpus may contain
older SPDX identifiers; identities are validated against legal's registry,
and unsupported IDs require review. Never infer `-only` versus `-or-later`
from a generic license text without a clear declaration.

When upgrading from 0.1.x, await `LicenseDetector.identify(text)`, which now
returns `Future<LicenseExpression?>`. Use `detect(dependency)` to retain review
findings alongside candidate terms.

Pana loads its corpus from its installed package when running from Dart source.
For a compiled **legal tool** or an application embedding its detector, ship the
local directory `pana-0.23.19/lib/src/third_party/spdx/licenses` and specify
`--license-data /path/to/licenses` or
`LicenseDetector(licenseDataDirectory: '/path/to/licenses')`. No network lookup
is performed. Pana caches its corpus per isolate; use one directory per isolate.
Applications that only distribute notices generated during their release do
not need this matcher or corpus in the distributed application.

This is **not** a source-file-level auditor: nested vendored code, native assets,
SDK/toolchain licenses, operating-system libraries, downloaded runtime assets,
and source availability obligations need separate attention. The root project's
own license is excluded. UTF-8 decoding or unreadable files fail the scan; empty
and unrecognized documents remain visible review findings. The output preserves
decoded document contents, including copyright and NOTICE, but adds section
boundaries and a final newline when necessary. No licensing decisions are inferred
from package popularity or dependency source.

## Programmatic API

```dart
import 'package:legal/legal.dart';

Future<void> main() async {
  final project = await LegalProject.load('.');
  final report = await project.scan();
  final result = report.check(project.config.policy);
  if (!result.isSuccess) {
    for (final finding in result.findings.where((f) => f.isFailure)) {
      print('${finding.package.dependency.name}: ${finding.message}');
    }
    return;
  }
  final text = report.renderThirdPartyLicenses(policy: project.config.policy);
  // Write or embed text using your application's own I/O layer.
  print(text);
}
```

`DependencyScanner`, `LicenseDetector`, `LicenseExpression`, `LicensePolicy`,
`LegalConfig`, and `LicenseReport` are separately usable. Collections are copied
and exposed unmodifiable. Expected scan/configuration errors use `LegalException`;
SPDX parser errors use `FormatException`. No global state or stdout is needed in
the core. `DependencyScanner.fromResolvedData` also accepts pre-collected pub JSON.

## CI and build integration

```yaml
- uses: dart-lang/setup-dart@v1
- run: dart pub get
- run: dart run legal check
- run: dart run legal generate --force --output dist/THIRD_PARTY_LICENSES.txt
```

This repository's CI additionally checks formatting, strict analysis, tests,
reproducible notices, API docs, and `dart pub publish --dry-run`. Fork pull
requests cannot trigger publishing.

There is deliberately **no build_runner builder in v1**. Root outputs can be
modeled by the build system, but subprocess graph discovery and license files
outside its asset graph would not provide sound incremental invalidation.
Run the CLI as an explicit release step instead of relying on a builder side
effect. A future builder can operate on a checked-in inventory asset. Embedding
notices is already possible through the renderer; Dart source generation is a
future extension rather than another output format in v1.

## Development and releases

Development uses the FVM SDK pin in `.fvmrc`; Melos and the committed VS Code
settings select that SDK. Consumers do not need FVM.

See [CONTRIBUTING.md](CONTRIBUTING.md) for FVM, Melos, Conventional Commits, offline
fixtures, hooks, and the first-publish setup. After that setup, releases use:

```sh
melos version
git push --follow-tags
```

Melos prints a prefilled GitHub release link. Once automated publishing is
enabled as described in CONTRIBUTING, GitHub Actions verifies
`v<pubspec version>` and publishes through the official
Dart reusable workflow using OIDC. No persistent pub credential is stored in
GitHub. Review the generated notice file for every distribution. This repository
dogfoods its runtime dependencies; its generated `THIRD_PARTY_LICENSES.txt` is
ignored by Git and rebuilt during checks.

When distributing the legal executable itself, include its own `LICENSE` and
`NOTICE.md` alongside the generated runtime dependency notices.

BSD-3-Clause licensed. Vendored detection data attribution is in
[NOTICE.md](NOTICE.md). Architecture rationale and
primary research sources are in [doc/architecture.md](doc/architecture.md).
