# 008: Add consistent C formatting and static analysis

**Status:** Proposed  
**Created:** 2026-11-15

## Summary

Adopt a small, repeatable C quality toolchain for `c-impl/`: use a checked-in
`clang-format` configuration to make source layout consistent, retain the
compiler warnings already enabled by CMake, and add a focused static-analysis
check in CI after validating its findings against this C11 project. Make
formatting a non-mutating CI check; provide a separate local command for
applying formatting. Keep all tools optional for production builds and avoid
formatting or linting Haskell sources.

The first rollout should format the existing C sources in a dedicated,
reviewable change. That change must contain no intentional behavior or design
changes. Static-analysis rules should be introduced incrementally, with
explicitly justified suppressions rather than broad warning exclusions.

## Motivation

The C code is difficult to scan in several places because declarations,
branches, validation, and error handling are compressed onto long lines. This
is most visible in `c-impl/src/main.c`, but also appears in the machine core,
unit tests, and benchmark harness. A formatter can establish consistent
indentation, wrapping, and brace layout. A linter or static analyzer can catch
some error-prone constructs and help keep future code consistent.

Formatting alone cannot improve names, decomposition, control flow, or
comments. Those should remain separate code review changes so formatting
churn does not conceal semantic edits. Existing compiler warnings and tests
remain necessary: static analysis cannot decide whether a valid result is the
intended result, and does not replace testing or review.

## Verified current state

- `c-impl/CMakeLists.txt` requires CMake 3.20 and C11. For GNU, Clang, and
  AppleClang it already enables `-Wall -Wextra -Wpedantic -Wconversion
  -Wshadow` on the core, with a narrower warning set for benchmarks.
- `.github/workflows/c-implementation.yml` runs CMake debug and sanitizer
  builds/tests on Ubuntu, plus a Haskell differential job. It has no formatter
  or static-analysis job.
- `c-impl/CMakePresets.json` uses Unix Makefiles and defines debug, release,
  sanitizer, and benchmark presets.
- `clang-format` supports C and can load repository style settings from a
  `.clang-format` file. The LLVM documentation lists multiple base styles and
  configurable options, so the repository can define its own stable subset
  instead of relying on each contributor's defaults.
- CMake supports a `C_CLANG_TIDY` target property and can pass the source file
  and compile command to clang-tidy. Cppcheck can consume a compilation
  database and reports error, warning, style, performance, and portability
  categories. Both tools need an agreed configuration and review of actual
  findings before their diagnostics become CI failures.

## Tool options

### Formatting: clang-format

Use `clang-format` as the one source formatter. It explicitly supports C,
works on individual files and ranges, and reads project configuration from
`.clang-format`. It does not parse project-specific intent or make code
structurally clearer; its value is predictable layout and easier review.

Start from LLVM style and set the project choices explicitly, including four
spaces per indent, a documented column limit, brace placement, and pointer
alignment. The current code already uses four-space block indentation. The
exact column limit and brace/pointer policy should be settled by reviewing a
formatted diff before committing the configuration. Pin the clang-format major
version used in CI and document it for local use, since formatting changes
between tool versions can create noisy diffs.

Provide two operations:

```sh
# Apply formatting locally to C sources
clang-format -i <c-impl C files>

# Check that committed sources already match the configured style
clang-format --dry-run --Werror <c-impl C files>
```

The check should cover `c-impl/src`, `include`, `tests`, and `benchmarks` C
files. It should not rewrite files in CI. `--dry-run` and `--Werror` are
documented clang-format options; CI should use a pinned version that supports
them. A small script or CMake custom target may centralize the file list, but
it must not be required by or run during a normal production build.

### Existing compiler warnings

Keep the current warning flags as the always-on, low-friction baseline for
supported GNU-family compilers. Consider adding other warning flags only
after checking that the project's supported compiler matrix accepts them and
that they produce actionable diagnostics. Do not enable `-Werror` globally
without a compiler-version policy; differences between compilers can otherwise
block builds for warnings unrelated to correctness.

### Static analysis: Cppcheck and clang-tidy / Clang Static Analyzer

Cppcheck is a reasonable first standalone linter because it analyzes C and
C++, supports C11 mode, can read a CMake compilation database, and provides
separate style and performance diagnostics in addition to bug-oriented
warnings. Its manual also notes that analysis is incomplete and should
complement tests and dynamic analysis. Run it against `c-impl/` with the
project's compile options, and begin with errors and warnings. Evaluate style
and performance categories in a pilot; promote only checks that produce
useful, understandable findings for this codebase. The performance category
describes suggestions based on common knowledge, not guaranteed speedups, so
never treat its advice as a measured optimization result.

Clang tooling is an alternative and useful second analyzer. The Clang Static
Analyzer explicitly targets C, C++, and Objective-C and performs
path-sensitive, interprocedural analysis. `clang-tidy` can be wired through
CMake's C target property, but its checks come from multiple language-oriented
families; select and validate C-compatible checks rather than enabling every
check group by default. A compile database is the preferred way for clang-tidy
to reuse actual compiler options. If adopted, keep this check in a separate
Clang-based CI job so developers using GCC or another compiler do not need to
change their normal build.

Do not install both Cppcheck and clang-tidy as mandatory contributor
dependencies at the start. Pilot Cppcheck first as the compact linter; if its
findings do not adequately cover path-sensitive defects, add a separate Clang
Static Analyzer job or clang-tidy profile. Avoid duplicate rules whose only
effect is to create competing style advice.

## Proposed repository changes

Add or update:

```text
4917-longest-string-advanced/
├── .clang-format
├── .github/workflows/c-implementation.yml
└── c-impl/
    ├── CMakeLists.txt
    ├── README.md
    └── scripts/check-format.sh       # optional helper if useful
```

The formatter's supported C file set is `src/*.c`, `include/**/*.h`,
`tests/*.c`, and `benchmarks/*.c`. The checked-in config should favor readable
multi-line control flow and avoid alignment rules that make small edits
reformat many unrelated lines.

For Cppcheck, configure CMake with `CMAKE_EXPORT_COMPILE_COMMANDS=ON` and the
existing C11 build options, then invoke Cppcheck with that compilation
database and a documented C11 setting if required by the chosen version. Keep
generated build directories and Haskell files out of its input. If CMake
integration via its `C_CPPCHECK` target property is selected, expose it as an
opt-in developer/CI setting rather than enabling it for every build; check
whether the chosen integration works with the project's CMake minimum and
generator. Alternatively, call the tool directly from its own CI step to
avoid introducing a build-system dependency.

CI should have an isolated style/static-analysis job. Pin tool versions using
the repository's chosen CI installation mechanism. The existing build and
test jobs remain unchanged and continue to run regardless of optional local
tool availability. The documented local commands should match CI exactly.

## Rollout plan

1. **Choose style and tool versions.** Produce a sample `clang-format` diff on
   one source file and review it. Set explicit formatting choices and pin a
   supported clang-format version.
2. **Format the existing C code only.** Apply the agreed formatter to every
   supported C file in a dedicated commit. Keep the diff mechanical; do not
   rename variables, split functions, or change control flow in this commit.
   Run the existing C debug, release, sanitizer, and Haskell differential
   checks after the formatting change.
3. **Enforce formatter check.** Add a read-only CI check and a documented
   local check/fix workflow. Fail if formatting differs; never auto-commit or
   mutate files in CI.
4. **Pilot Cppcheck.** Enable analysis for C11 using the CMake compilation
   database. Review all current findings. Fix clear defects in separate code
   changes, tune false-positive-prone checks deliberately, and add a narrow
   suppression only when it has an adjacent reason or a documented suppression
   entry. Because the current C codebase is small, prefer fixing the initial
   actionable warnings over introducing a broad warning baseline.
5. **Promote stable checks to CI.** Make the selected Cppcheck checks fail the
   dedicated CI job. Document the exact local command and version. Revisit
   clang-tidy or Clang Static Analyzer only if a specific coverage gap remains.
6. **Improve structure separately.** Use later implementation changes to
   improve names, split argument parsing into readable helpers, or simplify
   functions. Keep those diffs behavior-focused and covered by the existing
   tests and differential checks.

## Suppression and maintenance policy

- Do not suppress a finding solely to get a green build. First verify whether
  it indicates a defect or a configuration mistake.
- Keep suppressions local and narrow. State why a finding is safe to retain;
  avoid global disables and unexplained line-number suppressions.
- Review formatter or analyzer version bumps as explicit toolchain changes.
  Regenerate formatting only when intentionally adopting a new formatter
  version, then inspect the entire resulting diff.
- Formatting is a consistency check, not a proxy for code quality. Reviewers
  should still ask whether names, control flow, function boundaries, comments,
  and tests make the C implementation understandable.
- Never use static-analysis performance suggestions as a substitute for the
  per-instruction and workload benchmarks. Benchmark any proposed optimization
  and preserve functional tests.

## Acceptance criteria

- A checked-in `.clang-format` defines the agreed C style and a pinned tool
  version is used in CI and documented for contributors.
- Every C source, header, test, and benchmark file in the stated scope passes
  a non-mutating formatter check.
- CI has a dedicated lint/style job and reports actionable diagnostics with
  file and line context.
- The analyzer uses C11 and the project's actual include paths and compile
  definitions. It does not silently analyze generated files or unrelated
  Haskell code.
- All suppressions are narrow and have an explanation.
- Existing C unit/property, sanitizer, and Haskell differential tests continue
  to pass after the formatting-only rollout and after any separately reviewed
  lint fixes.
- Normal production builds do not require formatter or analyzer packages and
  do not fetch them.

## Decisions to make during implementation

- The exact `clang-format` base version, major release, column limit, brace
  style, and pointer alignment.
- Whether the project CI should start with Cppcheck alone or also run a Clang
  Static Analyzer job after a pilot.
- Which Cppcheck diagnostic categories and checks are sufficiently precise to
  enforce as CI failures.
- Whether to centralize commands in a helper script, CMake targets, or both.
- Whether hosted CI's Ubuntu image is an acceptable place to pin the tools, or
  a versioned container is needed for stable availability.

## References

- [ClangFormat documentation](https://clang.llvm.org/docs/ClangFormat.html)
  documents C support, command-line use, and non-mutating formatting options.
- [Clang-Format style options](https://clang.llvm.org/docs/ClangFormatStyleOptions.html)
  documents predefined styles and `.clang-format` configuration.
- [CMake `C_CLANG_TIDY` target property](https://cmake.org/cmake/help/latest/prop_tgt/LANG_CLANG_TIDY.html)
  documents CMake's compiler-command integration for clang-tidy.
- [Clang Static Analyzer documentation](https://clang.llvm.org/docs/ClangStaticAnalyzer.html)
  describes its C support and path-sensitive interprocedural analysis.
- [Cppcheck manual](https://cppcheck.sourceforge.io/manual.html) documents
  C11 mode, compilation database use, diagnostic categories, and the limits
  of static analysis.
