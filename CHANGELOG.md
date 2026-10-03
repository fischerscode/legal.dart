## Unreleased

- Add optional Dart SDK license inventory to CLI, configuration and API, with
  automatic SDK discovery during source execution and explicit build SDK paths.
- Accept additional runtime license/notice files and include SDK evidence in
  policy checks, JSON and generated notices.

## 0.2.1

 - **FIX**: allow both verified pana versions 0.23.18 and 0.23.19. ([98d16abd](https://github.com/fischerscode/legal.dart/commit/98d16abdb8ac5f82a516492000c71af462aa97c9))

## 0.2.0

> Note: This release has breaking changes.

 - **BREAKING** **FEAT**: use pana for offline license recognition. ([8e93620c](https://github.com/fischerscode/legal.dart/commit/8e93620c3f04123443ac26357dd9917d24c84cbe))
 - **BREAKING** **FEAT**: require confirmation before overwriting generated files. ([1199da9a](https://github.com/fischerscode/legal.dart/commit/1199da9a26ae6ea52df2f0baec06fd4cff0ed10b))

## 0.1.1

 - **FEAT**: add dependency license inventory and policy checks. ([bd8c26ff](https://github.com/fischerscode/legal.dart/commit/bd8c26ff0b368cbd3f02329c271f4ca60c610f51))

