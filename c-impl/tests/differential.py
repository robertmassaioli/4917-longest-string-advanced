#!/usr/bin/env python3
"""Batch bounded program runs through Haskell and compare the C JSON API."""
import argparse
import json
import random
import subprocess

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--c', required=True)
    parser.add_argument('--stack', required=True)
    parser.add_argument('--haskell-dir', required=True)
    args = parser.parse_args()
    subprocess.run([args.stack, 'build', 'cli4917:exe:4917-oracle'], cwd=args.haskell_dir,
                   text=True, capture_output=True, timeout=180, check=True)
    cases = [([3,4,1,8,10,0], 30), ([8,1,13,0], 31), ([11,0,13,0], 30),
             ([14,4,3,0,7], 20), ([8,9,8,10,8,15,0], 50)]
    rng = random.Random(0x4917)
    for _ in range(250):
        size = rng.randint(1, 16)
        cases.append(([rng.randrange(16) for _ in range(size)], rng.randint(0, 100)))
    rows = ''.join('run|' + ','.join(map(str, p)) + '|' + str(n) + '\n' for p, n in cases)
    oracle = subprocess.run([args.stack, 'exec', '--', '4917-oracle'], cwd=args.haskell_dir,
                            input=rows, text=True, capture_output=True, timeout=180, check=True).stdout.splitlines()
    if len(oracle) != len(cases):
        raise SystemExit(f'oracle returned {len(oracle)} rows for {len(cases)} cases')
    for index, ((program, limit), expected) in enumerate(zip(cases, oracle)):
        result = subprocess.run([args.c, 'run', '--program', ','.join(map(str, program)),
                                 '--max-steps', str(limit), '--json'], text=True,
                                capture_output=True, timeout=3, check=True)
        got = json.loads(result.stdout); fields = expected.split('\t')
        want = {'termination': fields[0], 'steps': fields[1], 'output_values': [int(x) for x in fields[2].split(',') if x],
                'memory': [int(x) for x in fields[3].split(',')], 'r0': int(fields[4]), 'r1': int(fields[5]),
                'pc': int(fields[6]), 'output_characters': fields[7]}
        for key, value in want.items():
            if got[key] != value:
                raise SystemExit(f'case {index} {program=} {limit=} {key}: C={got[key]!r}, Haskell={value!r}')
    # Compare arbitrary valid states and one-step events independently of
    # program initialization, including every opcode and every fetch address.
    step_cases = []
    for pc in range(16):
        for opcode in range(16):
            memory = [rng.randrange(16) for _ in range(16)]; memory[pc] = opcode
            step_cases.append((memory, rng.randrange(16), rng.randrange(16), pc, rng.randrange(1000)))
    step_cases.extend(([rng.randrange(16) for _ in range(16)], rng.randrange(16), rng.randrange(16),
                       rng.randrange(16), rng.randrange(1000)) for _ in range(256))
    step_rows = ''.join('step|' + ','.join(map(str, memory)) + f'|{r0}|{r1}|{pc}|{output}\n'
                        for memory, r0, r1, pc, output in step_cases)
    step_oracle = subprocess.run([args.stack, 'exec', '--', '4917-oracle'], cwd=args.haskell_dir,
                                 input=step_rows, text=True, capture_output=True,
                                 timeout=180, check=True).stdout.splitlines()
    if len(step_oracle) != len(step_cases):
        raise SystemExit(f'oracle returned {len(step_oracle)} step rows for {len(step_cases)} cases')
    for index, (case, expected) in enumerate(zip(step_cases, step_oracle)):
        memory, r0, r1, pc, output = case
        result = subprocess.run([args.c, 'step', '--memory', ','.join(map(str, memory)), '--r0', str(r0),
                                 '--r1', str(r1), '--pc', str(pc), '--output-characters', str(output), '--json'],
                                text=True, capture_output=True, timeout=3, check=True)
        got = json.loads(result.stdout); fields = expected.split('\t')
        want = {'event_value': int(fields[0]) if fields[0] else None, 'halted': fields[1] == 'True',
                'memory': [int(x) for x in fields[2].split(',')], 'r0': int(fields[3]), 'r1': int(fields[4]),
                'pc': int(fields[5]), 'output_characters': fields[6]}
        for key, value in want.items():
            if got[key] != value:
                raise SystemExit(f'step case {index} {case=} {key}: C={got[key]!r}, Haskell={value!r}')
    # The two-cell exhaustive C search must agree with an unpruned Haskell-core
    # baseline over precisely the same candidate vectors and bounded policy.
    length, limit = 2, 10000
    candidates = [[a, b] for a in range(16) for b in range(16)]
    search_rows = ''.join('run|' + ','.join(map(str, p)) + '|' + str(limit) + '\n' for p in candidates)
    search_oracle = subprocess.run([args.stack, 'exec', '--', '4917-oracle'], cwd=args.haskell_dir,
                                   input=search_rows, text=True, capture_output=True,
                                   timeout=180, check=True).stdout.splitlines()
    winners = []; best = -1; complete = 0
    for program, row in zip(candidates, search_oracle):
        fields = row.split('\t')
        if fields[0] == 'halted':
            complete += 1; score = int(fields[7])
            if score > best: best = score; winners = [program]
            elif score == best: winners.append(program)
    c_search = subprocess.run([args.c, 'search', '--length', str(length), '--max-steps', str(limit), '--json'],
                              text=True, capture_output=True, timeout=10, check=True)
    got_search = json.loads(c_search.stdout)
    if (int(got_search['candidate_count']) != len(candidates) or int(got_search['completed']) != complete or
        int(got_search['best_output_characters']) != best or int(got_search['winner_count']) != len(winners) or
        got_search['first_winner'] != winners[0]):
        raise SystemExit(f'search differs from exhaustive Haskell baseline: C={got_search}, Haskell best={best}, winners={len(winners)}')
    print(f'differential checks passed: {len(cases)} bounded runs, {len(step_cases)} single steps, and exhaustive length-2 search (seed 0x4917)')

if __name__ == '__main__': main()
