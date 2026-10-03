# Contributing

Use Git and [FVM](https://fvm.app/documentation/getting-started/installation).
The committed `.fvmrc` pins Flutter 3.47.5, including Dart 3.13.4. FVM supplies
the development SDK; the package itself remains Pure Dart. This repository contains
one publishable package in the root; fixture packages are test data, not workspace
members. Melos 8 uses configuration in `pubspec.yaml`, `workspace: []`, and
`useRootAsPackage: true`. A separate melos.yaml is not needed.

```sh
fvm use --force --skip-pub-get
fvm dart pub get
fvm dart run melos bootstrap
fvm dart run melos run analyze
fvm dart run melos run test
fvm dart run melos run format
fvm dart run melos run check
fvm dart doc
```

To use the shorter `melos` command, install the launcher:

```sh
fvm dart pub global activate melos
melos run check
```

The launcher delegates to the pinned local project dependency. Melos uses
`sdkPath: .fvm/flutter_sdk`, so its scripts use the FVM-selected SDK as well. `check` runs
format verification, strict analysis, tests, dogfooding policy, and publish dry
run. CI also generates the dogfood notice twice and compares bytes. The generated
file is intentionally ignored. Tests copy filesystem fixtures, resolve path
packages with `pub get --offline`, and create a local Git fixture. Their runtime
has no network requirement after repository dependencies have been installed.

Optional hooks (explicit local opt-in):

```sh
git config core.hooksPath .githooks
```

`pre-commit` checks formatting and analysis, and `commit-msg` validates the
Conventional Commit header. Run the full test suite before submitting a PR.
Avoid adding dependencies unless needed; keep runtime dependencies separate from
development tools. Keep API docs, configuration diagnostics, deterministic output,
and fixture coverage current. Tests under `test/goldens/` are reviewed source
artifacts; update them deliberately when the documented output changes.

## VS Code

The committed `.vscode/settings.json` points the Dart extension at
`.fvm/flutter_sdk/bin/cache/dart-sdk` and the Flutter SDK at `.fvm/flutter_sdk`.
Install the recommended Dart extension, run `fvm use --force --skip-pub-get`, then
reload the window if it was already open. The SDK symlink under `.fvm/` is local
and ignored by Git; `.fvmrc` and `.vscode/` settings are committed. Formatting on
save uses the selected SDK. FVM's automatic settings rewrites are disabled to
keep these checked-in paths stable.

CI installs standalone stable Dart directly, verifying that the Pure Dart package
does not require Flutter or FVM. Repository development and local releases use
FVM; consumers can continue to use ordinary `dart` commands. When updating the
SDK pin, verify the new bundled Dart version against pubspec and the lockfile.

## Conventional Commits

Examples:

```text
feat: add SPDX expression support
fix: detect LICENCE files
docs: improve policy documentation
feat!: change policy configuration format
```

Features produce minor releases, fixes patch releases, and breaking changes major
releases for stable packages. Before 1.0.0 Melos 8.9 uses patch bumps for non-breaking changes (including
features) and a minor bump for breaking changes; review its proposed version. Documentation-only changes normally do not
trigger a release. Breaking changes can also use a `BREAKING CHANGE:` footer.

## Updating the license matcher

`pana` is constrained to `>=0.23.18 <0.23.20` because the standalone matcher lives under
`package:pana/src/`. All access is isolated in
`lib/src/licenses/pana_adapter.dart`; no pana types appear in the public API.
Both supported versions have identical matcher code and SPDX corpus.
Before changing the constraint, inspect the upstream API, corpus identifiers, caching,
token-range semantics and matching thresholds. Run the full suite, including
the offline fixture and compiled CLI tests, then `dart run legal check` and
deterministic generation. Review newly flagged evidence before adding or
changing any version-bound overrides. The root policy currently records a
review of html 0.15.7's MIT terms and contributor attribution list.

`LicenseDetector.identify` is asynchronous with the pana backend. Consumers
upgrading from 0.1.x must await it; use `detect` to retain review diagnostics.

## Publishing setup

The first version of a new package must be published manually before pub.dev
allows automated publishing. This has already been completed for `legal`.
For a new package, run these commands from the exact release checkout:

```sh
fvm dart pub publish --dry-run
fvm dart pub publish
```

Follow pub's account authorization prompts. The pub.dev account must be able to
claim the package name. If using a verified publisher, transfer the package to
it after initial publication using the package administration page.

Configure automated publishing for subsequent releases:

1. On pub.dev, open **Admin → Automated publishing** for `legal`. Authorize GitHub
   repository `fischerscode/legal.dart`, tag pattern `v{{version}}`. Enable
   **Require GitHub Actions environment** with environment name `pub.dev`.
2. In GitHub, create an environment named `pub.dev`. Restrict it to release tags;
   add required reviewers if desired. Releases await their approval when enabled.
3. Configure branch protection for `main` and require CI. No persistent Pub
   credential or Pub credential secret is needed.

After setup, every new matching release tag triggers verification and publication.
Do not rerun publication for an already published version.

## Subsequent releases

Start from a clean, up-to-date `main` with Conventional Commits and baseline tags:

```sh
git pull --ff-only
git fetch --tags
melos run check
melos version
git show --stat HEAD
git push --follow-tags
```

`melos version` analyzes Conventional Commits, updates `pubspec.yaml` and
`CHANGELOG.md`, creates a release commit, and creates an annotated plain version
tag such as `v0.2.0`. Root-package version tags use this format automatically.
Tag fetching is explicit (`git fetch --tags`) so versioning cannot implicitly
pull/merge the branch. It does not push. Review the version and changelog before
pushing. It also prints the prefilled GitHub release link for every release.

Tag pushes matching `v*` in the canonical repository trigger verification.
The validation job installs stable Dart, verifies an exact SemVer tag match with
the pubspec version,
runs the same CI checks, and validates the package dry run. On success the official
reusable `dart-lang/setup-dart/.github/workflows/publish.yml` publishes using a
short-lived OIDC token in environment `pub.dev`. External actions and the reusable
publish workflow use major-version tags (`actions/checkout@v7` and
`dart-lang/setup-dart@v1`). Only the publish job receives `id-token: write`; other jobs have
`contents: read`. There is no publishing on PRs, including fork PRs.

Use `git push` and `git push origin <release-tag>` separately if preferred.
`--follow-tags` pushes reachable annotated tags missing on the remote, including
older ones. Push only new, unpublished release tags. Avoid `git push --tags` if
you have unrelated local tags.

Primary references: [Melos root packages](https://melos.invertase.dev/configuration/overview),
[Conventional versioning](https://melos.invertase.dev/commands/version), and
[pub.dev automated publishing](https://dart.dev/tools/pub/automated-publishing).
