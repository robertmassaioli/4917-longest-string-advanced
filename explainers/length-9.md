# Length-9 exhaustive search

## Search result

The C++ search CLI exhaustively evaluated all `16^9 = 68,719,476,736` nine-nibble programs. Each candidate occupies memory cells 0–8, with cells 9–15 zero-padded. The search counts output characters for programs that halt; programs that repeat a machine state are classified as cycles and do not qualify. The exhaustive search completed with no execution errors.

| Result | Count |
| --- | ---: |
| Candidates searched | 68,719,476,736 |
| Halted | 60,931,421,044 |
| Cycled | 7,788,055,692 |
| Errors | 0 |
| Maximum output length | 678 characters |
| Tied winners | 1 |

The unique winning program is:

```text
[8, 8, 13, 1, 14, 5, 2, 6, 15]
```

Replaying it with the C++ `run` command halted after 1,825 instructions and emitted 452 values. The output alternates `8, 13` for 226 pairs. Since `8` takes one decimal character and `13` takes two, the total is `226 × (1 + 2) = 678` characters.

Because every candidate in the length-9 domain was checked and the search reported zero errors, 678 is the maximum score for length 9 under this machine and scoring rule. This result does not imply anything about longer program lengths.

## Method and commands

The search used the release build of the `c-impl` CLI. That directory's implementation is C++17 and exposes the processor core through a C ABI; the exhaustive search itself runs through its `4917-cpp` executable.

From `c-impl/`, the build and search commands were:

```sh
cmake --preset release
cmake --build --preset release -j 4
/usr/bin/time -p ./build/make-release/4917-cpp search --length 9 --json
```

The search command took **7,558.18 seconds** wall-clock (2 hours, 5 minutes, 58.18 seconds), with 7,508.51 seconds user CPU time and 41.18 seconds system CPU time. Its JSON result was:

```json
{"schema":"4917-search-v2","length":9,"candidate_count":"68719476736","halted":"60931421044","cycled":"7788055692","errors":"0","exhaustive":true,"best_output_characters":"678","winner_count":"1","first_winner":[8,8,13,1,14,5,2,6,15]}
```

The winner replay command was:

```sh
./build/make-release/4917-cpp run \
  --program 8,8,13,1,14,5,2,6,15 \
  --max-steps 1000000 --json
```

It returned `termination: halted`, `steps: 1825`, and `output_characters: 678`.

## Haskell CLI generalization

The Haskell CLI generalizer was also run on the winning nine-nibble program:

```sh
cd haskell-impl
stack run -- generalize --program 8,8,13,1,14,5,2,6,15
```

It reports a halted execution in 1,825 steps with 678 output characters. Its
optimized 16-cell memory pattern requires addresses 0–10 and leaves addresses
11–15 unused:

```text
[8, 8, 13, 1, 14, 5, 2, 6, 15, 0, 0, Any(0-15), Any(0-15), Any(0-15), Any(0-15), Any(0-15)]
```

The generalizer counts all 16-cell memories, so it reports `16^16` possible
images reduced to `16^5 = 1,048,576` images. The length-9 search domain fixes
cells 9–15 to zero padding; within that domain, every one of the first nine
cells is required, so this pattern admits only the winning length-9 program.
The exhaustive search above, rather than this single-run generalization, is
what establishes the length-9 maximum.

## Interpretation

The winner is a loop-based program that emits an alternating pair of values 226 times before halting. The nine-nibble layout is longer than the previously documented length-8 winners, and its unique maximum is 196 characters above length 8's 482-character maximum. This is a comparison of these two exhaustive results; it does not establish a general growth pattern.
