# Contributing

Use stable Dart (currently tested with 3.13.4) and Git. This repository contains
one publishable package in the root; fixture packages are test data, not workspace
members. Melos 8 uses configuration in `pubspec.yaml`, `workspace: []`, and
`useRootAsPackage: true`. A separate melos.yaml is not needed.

```sh
dart pub get
dart run melos bootstrap
dart run melos run analyze
dart run melos run test
dart run melos run format
dart run melos run check
dart doc
```

To use the shorter `melos` command, install the launcher:

```sh
dart pub global activate melos
melos run check
```

The launcher delegates to the pinned local project dependency. `check` runs
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

The first version is **0.1.0**, as recorded in pubspec.yaml and CHANGELOG.md.
Its changelog is intentionally written by hand to describe the initial release.
Melos uses Git tags and Conventional Commits to determine subsequent changes;
the existing changelog entry does not trigger a version bump. Do not run
`melos version` before this first manual publication.

Create the public repository `https://github.com/fischerscode/legal.dart`, then
commit and push the implementation:

```sh
git add .
git commit -m "feat: add dependency license inventory and policy checks"
git remote add origin git@github.com:fischerscode/legal.dart.git
git push -u origin main
```

If origin already exists, use its configured URL rather than adding it again.
Wait for GitHub CI to pass. From the committed checkout, publish once manually:

```sh
dart pub publish --dry-run
dart pub publish
```

Follow pub's account authorization prompts. The pub.dev account must be able to
claim the package name `legal`. If using a verified publisher, transfer the
package to it after initial publication using the package administration page.

After publication succeeds, tag the **exact commit that was published** and
push the baseline tag so all clones share the same release history:

```sh
git tag -a v0.1.0 -m "Release legal 0.1.0"
git push origin v0.1.0
```

The Publish workflow explicitly excludes `v0.1.0`, since that historical bootstrap
release is published manually. It will not attempt a duplicate publication.
If you change the first version before publishing, update that tag exclusion and
the initial-release instructions to match.

Then enable automated publishing:

1. On pub.dev, open **Admin → Automated publishing** for `legal`. Authorize GitHub
   repository `fischerscode/legal.dart`, tag pattern `v{{version}}`.
2. In GitHub, create an environment named `pub.dev`. Restrict it to release tags;
   add required reviewers if desired. Releases await their approval when enabled.
3. Configure branch protection for `main` and require CI. No persistent Pub
   credential or Pub credential secret is needed.

First-publish authorization, repository creation/push, environment setup, and
pub.dev settings are owner actions; the development task has not published it.

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
pull/merge the branch. It does not push. Review the version and changelog before pushing. For the initial
release, use the manual procedure above rather than bumping an unpublished
version inadvertently.

Only a tag push matching `v*` in the canonical repository triggers publish, with
`v0.1.0` excluded as the historical manual bootstrap release. The validation job
installs stable Dart, verifies an exact SemVer tag match with the pubspec version,
runs the same CI checks, and validates the package dry run. On success the official
reusable `dart-lang/setup-dart/.github/workflows/publish.yml` publishes using a
short-lived OIDC token in environment `pub.dev`. The workflow is pinned to a
reviewed commit. Only the publish job receives `id-token: write`; other jobs have
`contents: read`. There is no publishing on PRs, including fork PRs.

Use `git push` and `git push origin <release-tag>` separately if preferred.
`--follow-tags` pushes reachable annotated tags missing on the remote, including
older ones. The initial baseline is already pushed and explicitly excluded from
publishing. Avoid `git push --tags` if you have unrelated local tags.

Primary references: [Melos root packages](https://melos.invertase.dev/configuration/overview),
[Conventional versioning](https://melos.invertase.dev/commands/version), and
[pub.dev automated publishing](https://dart.dev/tools/pub/automated-publishing).
