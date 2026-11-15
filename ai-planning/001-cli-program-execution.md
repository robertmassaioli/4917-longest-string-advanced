# 001: Direct program execution in the CLI

**Status:** Proposed  
**Created:** 2026-11-15

## Summary

Add a `run` command to `4917-cli` that accepts a 4917 program, executes it, and
shows the values it prints. This gives users a direct way to try a program
without starting a search or editing a source file.

## Motivation

The CLI currently has `demo`, `optimize-demo`, `cache-demo`, `search`, and
`solve` commands. `demo` executes only built-in examples. `solve` currently
does not execute user-supplied tasks, and there is no command for running an
arbitrary program. The processor implementation can execute a `Device`, but
the CLI does not expose that capability.

## Proposed interface

Add a command with syntax along these lines:

```text
4917-cli run --program 8,15,0 --max-steps 1000
```

The program argument is a comma-separated sequence of memory bytes. Each byte
must be an integer from 0 through 15, and the sequence must fit in the 16-byte
memory. The step limit is optional and should have a documented default.

For the example, the CLI should execute `PRINT 15; HALT` and display the
printed value (`15`) plus a short execution summary. It should preserve the
processor's existing decimal output convention, including two-character
values from 10 through 15.

## Behavior

- Parse and validate the full program before execution. Reject empty input,
  malformed integers, values outside 0–15, and programs longer than memory.
- Initialize the processor using the supplied bytes and the existing 4917
  memory semantics.
- Show the sequence of values printed, not only the aggregate output length.
- Stop normally when the program halts. Report a detected loop distinctly
  from a halt, and report when the configured step limit is reached.
- Keep `search` and `solve` behavior separate; this command runs exactly the
  supplied program and does not search for a better one.

The current processor APIs include loop-aware execution and an output-counting
path. Implementation should check whether those APIs retain the individual
printed values. If they do not, add a small execution result API that collects
the output sequence while reusing the same instruction semantics and loop
detection.

## Acceptance criteria

1. `4917-cli run --help` documents the program format and step-limit behavior.
2. A valid halting program prints its values in order and reports successful
   termination.
3. A looping program and a step-limit exhaustion are reported distinctly from
   normal termination.
4. Invalid program input produces a useful error and a non-zero exit status.
5. Existing CLI commands continue to work.

## Out of scope

- Assembling mnemonic source code; input remains numeric machine code.
- Searching, optimizing, or rewriting the supplied program.
- Adding a C implementation of the processor.
