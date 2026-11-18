# Repository guidance

## AI planning proposals

- Before creating a proposal in `ai-planning/`, run `bun run ai-planning/validate-proposals.ts --next` and use the returned number in the filename and heading.
- Name proposals `NNN-short-description.md`, include a `Created` date, and keep the sequence consecutive.
- After creating or renaming a proposal, run `bun run ai-planning/validate-proposals.ts` and resolve any reported numbering errors.
- The validator checks filenames, duplicate numbers, and gaps; it does not verify chronological creation order.
