# AI planning

This directory contains numbered design proposals for the repository.

## Proposal numbering

- Name each proposal `NNN-short-description.md`, with a zero-padded decimal
  number of at least three digits (for example, `001-cli-program-execution.md`).
- Number proposals consecutively from `001`. Do not reuse a number or leave a
  gap.
- `README.md` and tooling files such as `validate-proposals.ts` are supporting
  files, not proposals, and do not receive proposal numbers.
- Before creating a proposal, ask the validator for the next number:

  ```sh
  bun run ai-planning/validate-proposals.ts --next
  ```

- Validate the numbering with:

  ```sh
  bun run ai-planning/validate-proposals.ts
  ```

The validator checks proposal filenames, duplicate numbers, and gaps. It only
prints a next number when the existing proposal set is valid.
