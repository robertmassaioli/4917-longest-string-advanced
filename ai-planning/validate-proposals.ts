#!/usr/bin/env bun

import { readdirSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const usage = `Usage: bun run ai-planning/validate-proposals.ts [--next] [directory]

Validate proposal filenames and sequential numbering in a directory.
With --next, print the next zero-padded proposal number instead of a summary.
The directory defaults to the directory containing this script.`;

type Proposal = {
  filename: string;
  number: number;
};

function fail(message: string): never {
  console.error(`Proposal validation failed: ${message}`);
  process.exit(1);
}

function parseArgs(args: string[]): { next: boolean; directory: string } {
  let next = false;
  let directory: string | undefined;

  for (const arg of args) {
    if (arg === "--help" || arg === "-h") {
      console.log(usage);
      process.exit(0);
    } else if (arg === "--next") {
      next = true;
    } else if (arg.startsWith("-")) {
      fail(`unknown option: ${arg}\n\n${usage}`);
    } else if (directory !== undefined) {
      fail(`only one directory may be provided\n\n${usage}`);
    } else {
      directory = arg;
    }
  }

  const defaultDirectory = dirname(fileURLToPath(import.meta.url));
  return {
    next,
    directory: resolve(directory ?? defaultDirectory),
  };
}

function readProposals(directory: string): Proposal[] {
  let filenames: string[];
  try {
    filenames = readdirSync(directory, { withFileTypes: true })
      .filter((entry) => entry.isFile() && entry.name.endsWith(".md"))
      .map((entry) => entry.name)
      .filter((name) => name !== "README.md");
  } catch (error) {
    fail(`cannot read directory '${directory}': ${String(error)}`);
  }

  const proposals: Proposal[] = [];
  const filenamePattern = /^(\d{3,})-([a-z0-9]+(?:-[a-z0-9]+)*)\.md$/;

  for (const filename of filenames) {
    const match = filenamePattern.exec(filename);
    if (!match) {
      fail(`'${filename}' must follow NNN-short-description.md`);
    }

    const prefix = match[1];
    const number = Number(prefix);
    const canonicalPrefix = String(number).padStart(3, "0");
    if (!Number.isSafeInteger(number) || number < 1 || prefix !== canonicalPrefix) {
      fail(`'${filename}' has a non-canonical proposal number; expected at least three digits, zero-padded`);
    }

    proposals.push({ filename, number });
  }

  return proposals.sort((a, b) => a.number - b.number || a.filename.localeCompare(b.filename));
}

function validateSequence(proposals: Proposal[]): void {
  const seen = new Map<number, string>();
  for (const proposal of proposals) {
    const existing = seen.get(proposal.number);
    if (existing) {
      fail(`duplicate number ${String(proposal.number).padStart(3, "0")}: '${existing}' and '${proposal.filename}'`);
    }
    seen.set(proposal.number, proposal.filename);
  }

  const missing: number[] = [];
  const lastNumber = proposals.at(-1)?.number ?? 0;
  for (let number = 1; number <= lastNumber; number += 1) {
    if (!seen.has(number)) missing.push(number);
  }

  if (missing.length > 0) {
    const formatted = missing.map((number) => String(number).padStart(3, "0")).join(", ");
    fail(`numbering has gaps: ${formatted}`);
  }
}

const options = parseArgs(process.argv.slice(2));
const proposals = readProposals(options.directory);
validateSequence(proposals);

const nextNumber = (proposals.at(-1)?.number ?? 0) + 1;
const formattedNextNumber = String(nextNumber).padStart(3, "0");

if (options.next) {
  console.log(formattedNextNumber);
} else {
  const count = proposals.length;
  console.log(`Proposal numbering is valid (${count} proposal${count === 1 ? "" : "s"}).`);
}
