# Metal search benchmark: Apple M4 Pro

**Date:** 2026-11-24  
**Hardware:** Apple M4 Pro, 20-core Metal 3 GPU  
**Build:** AppleClang 17, CMake Release, local CLI11 2.7.2 source fetched by CMake  
**GPU budget:** 256 instructions per candidate (default)  
**Batch size:** 262,144 candidates

The GPU solver and the existing CPU solver returned the same exhaustive result
for every measured length. The Metal solver sends every candidate that did not
halt during its GPU budget through the exact CPU cycle detector. Times below
include process startup, shader compilation, GPU work, and exact fallbacks.

| Length | Candidates | CPU wall time | Metal solver wall time | Speedup | GPU halted | CPU exact fallback | Best score |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 5 | 1,048,576 | 0.0788 s | 0.0794 s | 0.99× | 969,107 | 79,469 | 62 |
| 6 | 16,777,216 | 1.340 s | 0.639 s | 2.10× | 15,407,784 | 1,369,432 | 93 |
| 7 | 268,435,456 | 25.16 s | 10.92 s | 2.30× | 243,945,960 | 24,489,496 | 172 |

Lengths 5 and 6 are medians over three paired CPU/Metal process runs. Length 7
was one paired run because each exhaustive search took tens of seconds. The
length-7 rates were about 10.7 million candidates/second on CPU and 24.6
million candidates/second for the complete Metal solver. The Metal JSON's
`seconds` field starts after Metal device and kernel initialization; it was
10.688 seconds at length 7, compared with 10.92 seconds external wall time.

The common result fields matched exactly. In particular, length 7 classified
243,947,408 candidates as halted, 24,488,048 as cycles, and zero as errors.
The GPU halted 243,945,960 candidates within its budget; the CPU fallback
classified the remaining 24,489,496, including 1,448 later halts. The best
output was 172 characters, with 26 tied winners and first winner
`[1,8,10,14,4,1,15]`.

## Reproduction

```sh
cmake -S c-impl -B /tmp/4917-gpu-build -DCMAKE_BUILD_TYPE=Release
cmake --build /tmp/4917-gpu-build -j 8
/tmp/4917-gpu-build/4917-cpp search --length 7 --json
/tmp/4917-gpu-build/4917-metal-search --length 7 --json
```

These results are specific to this computer and run. GPU utilization, thermal
state, competing applications, and fallback mix affect speed. At length 5 the
Metal version was effectively tied with the CPU version; at lengths 6 and 7
the larger candidate batches produced a measured speedup. A GPU run is not
automatically faster for every search size.
