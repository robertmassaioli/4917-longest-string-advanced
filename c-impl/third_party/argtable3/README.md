# Argtable3 vendor record

- Upstream project: <https://github.com/argtable/argtable3>
- Version: 3.3.1
- Immutable source commit: `b50c6c81f25eef8af51141678b333c55b661414d`
- License: BSD-3-Clause; see `LICENSE` for the upstream license and notices
  for bundled components.
- Integration: selected upstream C sources are built as the private
  `4917_argtable3` static target. The target is linked only to `4917-c`.
- Fetch behavior: none. All required sources and license notices are checked
  into this repository, so normal and offline builds use the same pinned code.
- Platform verification: the project debug preset was built with AppleClang
  17 on macOS. Other compiler/platform combinations have not been verified by
  this integration change.

The vendored files are copied from the source tree at the commit above. To
update Argtable3, review the new upstream source and license notices, update
this record, and run the CMake build and CLI contract tests on the supported
platform matrix.
