## Unreleased

- Embed an offline, versioned native runtime license catalog and add `--sdk-target`
  / `sdk_target` selection. The initial Dart 3.13.4 / linux-x64 bundle is partial
  and preserves pinned upstream texts for seven native components.
- Report SDK runtime coverage separately from package license recognition in CLI,
  JSON and API. Incomplete or missing bundles fail `check` and require
  `--allow-incomplete` for generation, even when package policy approvals exist.

## 0.2.2

 - **FEAT**: include Dart SDK licenses in inventory and notices. ([20b97986](https://github.com/fischerscode/legal.dart/commit/20b97986f57ca719dc8d1a2f796fe41ffd5dae39))

## 0.2.1

 - **FIX**: allow both verified pana versions 0.23.18 and 0.23.19. ([98d16abd](https://github.com/fischerscode/legal.dart/commit/98d16abdb8ac5f82a516492000c71af462aa97c9))

## 0.2.0

> Note: This release has breaking changes.

 - **BREAKING** **FEAT**: use pana for offline license recognition. ([8e93620c](https://github.com/fischerscode/legal.dart/commit/8e93620c3f04123443ac26357dd9917d24c84cbe))
 - **BREAKING** **FEAT**: require confirmation before overwriting generated files. ([1199da9a](https://github.com/fischerscode/legal.dart/commit/1199da9a26ae6ea52df2f0baec06fd4cff0ed10b))

## 0.1.1

 - **FEAT**: add dependency license inventory and policy checks. ([bd8c26ff](https://github.com/fischerscode/legal.dart/commit/bd8c26ff0b368cbd3f02329c271f4ca60c610f51))

