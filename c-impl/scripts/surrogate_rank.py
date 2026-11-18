#!/usr/bin/env python3
"""Fit and use a small deterministic nearest-neighbour score ranker.

Predictions are search heuristics. Only a direct halted simulation is a score.
"""

import argparse
import hashlib
import json
import math
import sys
from pathlib import Path


SCHEMA = "4917-dataset-v1"
MODEL_SCHEMA = "4917-surrogate-knn-v1"


class InputError(ValueError):
    pass


def read_jsonl(path):
    rows = []
    try:
        with open(path, encoding="utf-8") as source:
            for line_number, line in enumerate(source, 1):
                if not line.strip():
                    continue
                try:
                    row = json.loads(line)
                except json.JSONDecodeError as exc:
                    raise InputError(f"{path}:{line_number}: invalid JSON: {exc.msg}") from exc
                if not isinstance(row, dict):
                    raise InputError(f"{path}:{line_number}: expected a JSON object")
                rows.append((row, f"{path}:{line_number}"))
    except OSError as exc:
        raise InputError(f"cannot read {path}: {exc}") from exc
    return rows


def validate_program(row, where):
    length = row.get("length")
    program = row.get("program")
    if isinstance(length, bool) or not isinstance(length, int) or not 1 <= length <= 16:
        raise InputError(f"{where}: length must be an integer from 1 through 16")
    if not isinstance(program, list) or len(program) != length:
        raise InputError(f"{where}: program must be a list with exactly length ({length}) nibbles")
    for position, nibble in enumerate(program):
        if isinstance(nibble, bool) or not isinstance(nibble, int) or not 0 <= nibble <= 15:
            raise InputError(f"{where}: program[{position}] must be an integer nibble from 0 through 15")
    return length, program


def score_target(row, where):
    status = row.get("status")
    if status not in ("halted", "cycle", "unresolved", "error"):
        raise InputError(f"{where}: status must be halted, cycle, unresolved, or error")
    target = row.get("output_characters")
    if status != "halted":
        if target is not None:
            raise InputError(f"{where}: non-halted rows must have null output_characters")
        return None
    if isinstance(target, bool) or not (isinstance(target, int) or
            isinstance(target, str) and target.isdecimal()):
        raise InputError(f"{where}: halted rows require an exact non-negative integer output_characters")
    value = int(target)
    if value < 0:
        raise InputError(f"{where}: output_characters cannot be negative")
    return value


def identity(length, program):
    return f"{length}:" + ",".join(map(str, program))


def parse_dataset(path):
    labeled = []
    for row, where in read_jsonl(path):
        if row.get("schema") != SCHEMA:
            raise InputError(f"{where}: schema must be {SCHEMA!r}")
        length, program = validate_program(row, where)
        score = score_target(row, where)
        if score is not None:
            labeled.append({"length": length, "program": program, "score": score})
    return labeled


def distance(a, b):
    # Length is an explicit feature: candidates of different declared lengths
    # never share neighbours. Within a length, every code cell has equal weight.
    if a["length"] != b["length"]:
        return math.inf
    return sum(x != y for x, y in zip(a["program"], b["program"]))


def predict(model, candidate, k):
    neighbors = sorted(model["examples"], key=lambda ex: (distance(ex, candidate),
                                                           identity(ex["length"], ex["program"])))
    neighbors = [ex for ex in neighbors if math.isfinite(distance(ex, candidate))][:k]
    if not neighbors:
        return None, 0
    exact = [ex["score"] for ex in neighbors if ex["program"] == candidate["program"]
             and ex["length"] == candidate["length"]]
    if exact:
        return sum(exact) / len(exact), len(neighbors)
    # Inverse Hamming-distance weighting favors structurally close examples.
    weights = [1.0 / distance(ex, candidate) for ex in neighbors]
    estimate = sum(w * ex["score"] for w, ex in zip(weights, neighbors)) / sum(weights)
    return estimate, len(neighbors)


def load_model(path):
    try:
        with open(path, encoding="utf-8") as source:
            model = json.load(source)
    except (OSError, json.JSONDecodeError) as exc:
        raise InputError(f"cannot load model {path}: {exc}") from exc
    if not isinstance(model, dict) or model.get("schema") != MODEL_SCHEMA:
        raise InputError(f"{path}: unsupported or malformed model (expected {MODEL_SCHEMA})")
    return model


def save_model(path, examples):
    model = {"schema": MODEL_SCHEMA, "description": "inverse-Hamming nearest-neighbour score estimate",
             "features": ["declared_length", "nibble_at_each_position"], "examples": examples}
    with open(path, "w", encoding="utf-8") as output:
        json.dump(model, output, sort_keys=True, separators=(",", ":"))
        output.write("\n")


def load_candidates(path):
    candidates = []
    for row, where in read_jsonl(path):
        length, program = validate_program(row, where)
        candidates.append({"length": length, "program": program})
    return candidates


def deterministic_split(examples, fraction):
    # Split by candidate identity so duplicate evaluations cannot leak across sides.
    train, test = [], []
    seen = set()
    for ex in examples:
        key = identity(ex["length"], ex["program"])
        if key in seen:
            continue
        seen.add(key)
        digest = hashlib.sha256(key.encode("ascii")).digest()
        (test if int.from_bytes(digest[:8], "big") / 2**64 < fraction else train).append(ex)
    if len(examples) > 1 and not test:
        test.append(train.pop())
    if len(examples) > 1 and not train:
        train.append(test.pop())
    return train, test


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    train = commands.add_parser("train", help="fit and save a score ranker")
    train.add_argument("--data", required=True, help="4917-dataset-v1 JSONL")
    train.add_argument("--model", required=True, help="output JSON model artifact")
    rank = commands.add_parser("rank", help="rank JSONL candidates by predicted score")
    rank.add_argument("--model", required=True)
    rank.add_argument("--input", required=True, help="JSONL objects with length and program")
    rank.add_argument("-k", type=int, default=5, help="number of neighbours (default: 5)")
    evaluate = commands.add_parser("evaluate", help="reproducible candidate-identity holdout evaluation")
    evaluate.add_argument("--data", required=True)
    evaluate.add_argument("--test-fraction", type=float, default=0.2)
    evaluate.add_argument("-k", type=int, default=5)
    args = parser.parse_args()
    try:
        if args.command == "train":
            examples = parse_dataset(args.data)
            if not examples:
                raise InputError(f"{args.data}: no halted exact-score rows to train on")
            save_model(args.model, examples)
            print(f"saved {len(examples)} halted examples to {args.model}")
        elif args.command == "rank":
            if args.k < 1:
                raise InputError("-k must be at least 1")
            model = load_model(args.model)
            candidates = load_candidates(args.input)
            ranked = []
            for candidate in candidates:
                score, count = predict(model, candidate, args.k)
                ranked.append({**candidate, "predicted_output_characters": score,
                               "neighbors_used": count})
            ranked.sort(key=lambda row: (row["predicted_output_characters"] is None,
                                         -(row["predicted_output_characters"] or 0),
                                         row["length"], row["program"]))
            for row in ranked:
                print(json.dumps(row, sort_keys=True, separators=(",", ":")))
        else:
            if not 0 < args.test_fraction < 1 or args.k < 1:
                raise InputError("test fraction must be between 0 and 1 and -k must be at least 1")
            examples = parse_dataset(args.data)
            train_rows, test_rows = deterministic_split(examples, args.test_fraction)
            if not train_rows or not test_rows:
                raise InputError("evaluation needs at least two distinct halted candidate identities")
            model = {"examples": train_rows}
            errors = []
            for row in test_rows:
                estimate, _ = predict(model, row, args.k)
                if estimate is not None:
                    errors.append((estimate, row["score"]))
            if not errors:
                raise InputError("holdout candidates have no training examples at their declared lengths")
            mae = sum(abs(pred - actual) for pred, actual in errors) / len(errors)
            rmse = math.sqrt(sum((pred - actual) ** 2 for pred, actual in errors) / len(errors))
            print(json.dumps({"train_candidates": len(train_rows), "test_candidates": len(test_rows),
                              "scored_test_candidates": len(errors), "k": args.k,
                              "mae": mae, "rmse": rmse}, sort_keys=True))
    except InputError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
