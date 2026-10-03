These tiny packages are copied into temporary directories and resolved with
`dart pub get --offline`. The app has a runtime path to `runtime -> shared, dual`
and a dev path to `dev -> dev_only, shared`. Although dual is declared as dev
in the app, it must remain in the runtime closure. Tests create a local Git
repository as a separate fixture; no hosted packages or network are needed.

License recognition tests load additional reference texts directly from the
SPDX corpus bundled with the pinned pana dependency; no separate copies or
network access are needed.
