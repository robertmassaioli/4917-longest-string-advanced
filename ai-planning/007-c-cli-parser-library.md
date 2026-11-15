# 007: Replace the C CLI's hand-written argument parser

**Status:** Proposed  
**Created:** 2026-11-15

## Summary

Replace the inline argument-scanning logic in `c-impl/src/main.c` with a
declarative command-line parser and a small command-specific validation layer.
The parser should make the supported syntax, required options, help text, and
parse errors visible in one place. Parsing remains in the C front end and must
not enter `4917_core` or affect processor behavior or execution performance.

The preferred candidate is Argtable3, subject to confirming its current CMake
integration, supported target platforms, and pinned release behavior in a small
implementation spike. It is an ANSI C parser with GNU-style options, automatic
usage/error support, a single-file distribution, and a BSD-3-Clause license.
If that integration or portability check fails the project's supported build
matrix, retain a small local parser with a clear command/option table rather
than introducing a platform-specific parser. The Haskell CLI remains an
independent interface and does not need to adopt the same library or syntax.

## Motivation and current behavior

The parser is currently part of `main` in `c-impl/src/main.c`. It scans every
argument with a chain of `strcmp` conditions, stores options in shared local
variables, and later dispatches to `run`, `search`, or `step`. The validation
and interpretation are split between that loop and the command handlers. As
commands/options grow, understanding which options apply to each command and
which combinations are valid requires mentally executing that loop.

Observed behavior in the current source that should be deliberately handled
when replacing it:

- `run` requires `--program`; `search` requires `--length`; `step` requires
  `--memory`, but only these required fields are checked before dispatch.
- `--max-steps` defaults to 10000, `--json` defaults off, and `step`'s
  `--r0`, `--r1`, `--pc`, and `--output-characters` default to zero.
- The parser accepts options in any order after the subcommand. Repeated
  options silently use the last value. It also accepts recognized options that
  are irrelevant to the selected command, then ignores them.
- Numeric conversion rejects empty strings, leading minus signs, trailing
  characters, and `strtoull` errors, but failures return exit code 2 without a
  diagnostic. Range validation happens later and differs by option.
- An option missing its value falls through to the generic usage error.
  Unknown arguments also show usage. `--help` and `-h` are only recognized
  before the subcommand; help after a subcommand is not handled specially.
- The positional subcommand is selected before option scanning. The parser has
  no explicit `--` behavior or positional-argument policy.

The proposal should preserve the documented command forms and defaults while
making invalid invocations consistent and adding tests for the actual CLI
contract. Where current behavior is accidental or ambiguous, implementation
should adopt the stricter policies below and record them in `c-impl/README.md`.

## Options considered

### Keep and refactor a local parser

The CLI currently has three commands and a modest option set. A small
hand-written table-driven parser could be dependency-free and preserve exact
control over CMake/offline builds. This remains the fallback if no library
meets the project's platform or integration needs. It would still require
implementing help generation, duplicate-option rules, command-specific
validation, and tests locally.

### POSIX `getopt`

`getopt` is a reasonable system facility for conventional short options and
avoids vendoring code. The POSIX interface is centered on short option
characters and `optarg` processing; it does not provide a declarative
subcommand schema or generated command-specific help. The current interface
uses long options such as `--max-steps`, so mapping those to short options or
writing additional long-option handling would leave much of the current parser
work in place. `getopt_long` is a common extension but is not the portable
POSIX interface. See the [POSIX `getopt` specification](https://pubs.opengroup.org/onlinepubs/9799919799/functions/getopt.html)
and the [GNU libc option-parsing documentation](https://sourceware.org/glibc/manual/latest/html_node/Parsing-Program-Arguments.html).

### GNU `argp`

GNU `argp` provides automatic help/version handling and composes independent
option parsers, which can suit subcommands. It is documented as part of the
GNU C Library rather than POSIX, so adopting it would bind the CLI to GNU libc
or require compatibility work on other C runtimes. That is not a good default
while the project's supported platforms are not explicitly Linux/glibc-only.
See [GNU libc's Argp documentation](https://sourceware.org/glibc/manual/latest/html_node/Argp.html).

### Argtable3 (preferred candidate)

Argtable3 describes itself as an ANSI C library for GNU-style options. Its
declarative argument tables, generated usage/error output, single-file
amalgamation, CMake support, and BSD-3-Clause license appear to fit this
project's C11/CMake application without requiring C++. The project documents
embedding the amalgamated source or using package managers. See the
[Argtable3 project and integration guide](https://github.com/argtable/argtable3),
its [license](https://github.com/argtable/argtable3/blob/master/LICENSE), and
the [Argtable tutorial](https://www.argtable.org/tutorial/).

The library documents that it is built on `getopt`; therefore, its ANSI C API
does not by itself prove that its implementation works on every target C
runtime. The spike must verify behavior on the actual supported compilers and
platforms. It should also check the pinned release and embedded-source
workflow, rather than relying on an unpinned download at configure time.

### `cofyc/argparse` (alternative library)

This C library explicitly supports subcommands, positional arguments, long
and short options, and automatic usage/error messages, under an MIT-style
license. Those features fit the interface well. Its API and build integration
should be compared in the same spike if Argtable3 does not meet requirements.
See the [project README and license](https://github.com/cofyc/argparse) and
[MIT license file](https://github.com/cofyc/argparse/blob/master/LICENSE).

The existence of these features is not by itself a reason to add a dependency:
the comparison should include maintenance/release evidence, exact subcommand
behavior, CMake integration, compiler coverage, error customization, and the
cost of vendoring or fetching it. Avoid selecting a library solely by stars or
an unverified claim of portability.

## Proposed command-line contract

Keep the current top-level forms and defaults:

```text
4917-c run --program CSV [--max-steps N] [--json]
4917-c search --length N [--max-steps N] [--json]
4917-c step --memory CSV --r0 N --r1 N --pc N [--output-characters N] [--json]
```

The parser layer should:

- Parse the subcommand first and then only that command's options. `--help` or
  `-h` at the top level prints general help; after a subcommand it prints help
  for that command. Help exits successfully.
- Reject unknown options, extra positional arguments, missing option values,
  repeated scalar options, and options that do not apply to the selected
  command. Show a concise diagnostic and the relevant usage text on stderr;
  retain exit code 2 for invalid invocation or input.
- Preserve defaults of 10000 max steps, JSON disabled, and zero for omitted
  `step` registers, PC, and output-character count. Keep `run` program, `search`
  length, and `step` memory required.
- Parse nonnegative decimal integers without overflow and keep semantic range
  checks close to dispatch: search length 1–4, machine state nibbles 0–15,
  maximum step count within the core's accepted bound, and output count within
  the supported counter range. Report invalid values instead of silently
  returning a status code.
- Continue validating program/memory CSV values through the existing domain
  validation, with diagnostics that distinguish command-line syntax errors
  from malformed program/state input. Do not let a parsing library interpret
  or normalize CSV contents.
- Keep output schemas, success/error exit-code meanings, core APIs, and machine
  semantics unchanged. No parser code or dependency may be linked into
  `4917_core`.

The stricter duplicate/irrelevant-option behavior is an intentional CLI
contract clarification. Confirm it in README and tests when implementing; do
not change JSON schemas as part of this proposal.

## Dependency and build policy

First implement a small throwaway spike using the exact commands and options
above. Choose Argtable3 if all of these checks pass:

1. It builds as C with the repository's C11 compiler baseline and integrates
   as a pinned source dependency in CMake.
2. A normal production build remains reproducible and does not silently fetch
   an unpinned dependency. Preserve the project's explicit offline build path;
   document whether the source is vendored, provided by a system package, or
   fetched only behind an explicit option.
3. The supported compiler/platform matrix builds it without relying on a
   nonportable libc extension. If the supported matrix includes Windows or a
   non-glibc runtime, verify there rather than infer portability from “ANSI C.”
4. Its license is compatible with this repository, and the exact vendored
   version/revision and license are recorded.
5. It supports separate command-specific option tables, help, required
   options, unknown/repeated-option detection, and the diagnostics needed by
   the contract without brittle wrapper code.

If Argtable3 fails, compare `cofyc/argparse` against the same list. If neither
passes, retain a table-driven local parser rather than introduce a portability
or maintenance burden. `getopt` may be used if the CLI is intentionally
redesigned around short options, but that would be a separate user-facing
decision and is not assumed here.

Any selected third-party parser belongs only to the `4917-c` executable. It
must not be a dependency of `4917_core`, C tests, or the benchmark executable.
The library should be linked in a way that keeps production builds independent
of network access after dependency setup and preserves the documented
dependency-free CMake mode where practical.

## Implementation and verification plan

1. Record the CLI syntax, defaults, range checks, and error/exit-code rules in
   `c-impl/README.md`; keep Haskell CLI behavior independent.
2. Complete the parser spike and document the chosen version, license,
   integration method, supported platforms tested, and offline behavior.
3. Move command selection, option parsing, and parser-specific structures out
   of the current compressed `main` logic into readable front-end functions.
   Keep numeric conversion, CSV parsing, and command handlers as clear layers;
   do not let the parser library own machine semantics.
4. Add CTest CLI cases for top-level and per-command help, all three valid
   command forms, defaults, missing required options, missing values, unknown
   and irrelevant options, duplicate options, extra arguments, malformed and
   out-of-range numbers, malformed CSV, and exit codes/diagnostic streams.
   Keep existing JSON integration expectations and core/property tests.
5. Verify debug and release CMake builds, CTest, sanitizer mode when supported,
   and the documented offline/configured-dependency path. Confirm a parser
   change cannot alter core or benchmark target linkage.

## Acceptance criteria

- The C CLI's supported syntax, defaults, validation, help, and failure modes
  are documented and covered by automated command-level tests.
- `main.c` no longer contains the current long chain of per-option string
  comparisons; command-specific options are declared together and readable.
- The chosen library satisfies the dependency, license, compiler, platform,
  and offline-build checks above, or the implementation uses the documented
  local-parser fallback with the same behavior and tests.
- Existing command output schemas, core behavior, and Haskell CLI remain
  unchanged.
- A normal CMake build and the CTest suite pass without introducing a network
  fetch as an implicit side effect.
