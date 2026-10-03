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

## First publication

Use Melos for the first release as well as subsequent ones. The current version
is an unpublished starting point; review the version proposed by Melos rather
than assuming the first published version. CHANGELOG.md has a placeholder until
Melos generates the first release entry from the implementation's feature commit.
No manually created baseline tag is needed.

Create the public repository `https://github.com/fischerscode/legal.dart`, commit
all changes, and start from a clean main branch:

```sh
git add .
git commit -m "chore: configure initial release workflow"
melos run check
melos version
git show --stat HEAD
git push -u origin main --follow-tags
```

If needed, first add the remote with
`git remote add origin git@github.com:fischerscode/legal.dart.git`.
`melos version` updates the version and changelog, commits them, creates the
annotated version tag, and prints a link to the prefilled GitHub release page
because `releaseUrl: true` is enabled. Push the commit and tag before opening
that link to review and create the GitHub release. The link does not itself
create a release; a GitHub release and a pub.dev publication are separate steps.

The tag triggers verification in GitHub, but automatic publication is initially
disabled. After CI succeeds, publish the exact tagged checkout once manually:

```sh
fvm dart pub publish --dry-run
fvm dart pub publish
```

Follow pub's account authorization prompts. The pub.dev account must be able to
claim the package name `legal`. If using a verified publisher, transfer the
package to it after initial publication using the package administration page.

Then enable automated publishing for future releases:

1. On pub.dev, open **Admin → Automated publishing** for `legal`. Authorize GitHub
   repository `fischerscode/legal.dart`, tag pattern `v{{version}}`.
2. In GitHub, create an environment named `pub.dev`. Restrict it to release tags;
   add required reviewers if desired. Releases await their approval when enabled.
3. Under **Settings → Secrets and variables → Actions → Variables**, create the
   repository variable `PUB_DEV_AUTOMATED_PUBLISHING` with value `true`.
   This is a non-secret switch, not a credential. Leave it unset until steps 1–2
   and the manual first publication are complete.
4. Configure branch protection for `main` and require CI. No persistent Pub
   credential or Pub credential secret is needed.

Enabling the switch does not rerun old tags. Do not rerun publication for the
already manually published initial version. First-publish authorization,
repository creation/push, environment setup, and pub.dev settings are owner
operations; the development task has not published it.

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
Publication also requires repository variable `PUB_DEV_AUTOMATED_PUBLISHING=true`. The validation job
installs stable Dart, verifies an exact SemVer tag match with the pubspec version,
runs the same CI checks, and validates the package dry run. On success the official
reusable `dart-lang/setup-dart/.github/workflows/publish.yml` publishes using a
short-lived OIDC token in environment `pub.dev`. The workflow is pinned to a
reviewed commit. Only the publish job receives `id-token: write`; other jobs have
`contents: read`. There is no publishing on PRs, including fork PRs.

Use `git push` and `git push origin <release-tag>` separately if preferred.
`--follow-tags` pushes reachable annotated tags missing on the remote, including
older ones. The first tag is pushed with automated publication still disabled; subsequent
release tags publish after the repository switch is enabled. Avoid `git push --tags` if you have unrelated local tags.

Primary references: [Melos root packages](https://melos.invertase.dev/configuration/overview),
[Conventional versioning](https://melos.invertase.dev/commands/version), and
[pub.dev automated publishing](https://dart.dev/tools/pub/automated-publishing).
