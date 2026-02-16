# Mathematical Proof: Why ADD/SUB Loop Cycles Exactly 31 Times

## The Program

```
[4, 1, 8, 15, 15]
```

**Decoded:**
- Byte 0: `4` = INC R1
- Byte 1: `1` = ADD (R0 = R0 + R1)
- Bytes 2-3: `8, 15` = PRINT 15
- Byte 4: `15` = JNZ (with implicit arg 0, jumps to byte 0 if R0 ≠ 0)

## Initial Conditions

- R0 = 0
- R1 = 0
- All arithmetic is modulo 16 (4-bit values wrap: 0-15)

## Execution Sequence

Each iteration performs:
1. **INC R1**: R1 = (R1 + 1) mod 16
2. **ADD**: R0 = (R0 + R1) mod 16
3. **PRINT 15**: Output "15"
4. **JNZ 0**: Jump to byte 0 if R0 ≠ 0, otherwise continue (halt)

The loop terminates when R0 = 0 after the ADD operation.

## Iteration-by-Iteration Analysis

| Iteration | R1 (before INC) | R1 (after INC) | R0 (before ADD) | R0 (after ADD) | Continue? |
|-----------|-----------------|----------------|-----------------|----------------|-----------|
| 1 | 0 | 1 | 0 | 0+1=1 | Yes |
| 2 | 1 | 2 | 1 | 1+2=3 | Yes |
| 3 | 2 | 3 | 3 | 3+3=6 | Yes |
| 4 | 3 | 4 | 6 | 6+4=10 | Yes |
| 5 | 4 | 5 | 10 | 10+5=15 | Yes |
| 6 | 5 | 6 | 15 | 15+6=21→5 | Yes |
| 7 | 6 | 7 | 5 | 5+7=12 | Yes |
| 8 | 7 | 8 | 12 | 12+8=20→4 | Yes |
| 9 | 8 | 9 | 4 | 4+9=13 | Yes |
| 10 | 9 | 10 | 13 | 13+10=23→7 | Yes |
| 11 | 10 | 11 | 7 | 7+11=18→2 | Yes |
| 12 | 11 | 12 | 2 | 2+12=14 | Yes |
| 13 | 12 | 13 | 14 | 14+13=27→11 | Yes |
| 14 | 13 | 14 | 11 | 11+14=25→9 | Yes |
| 15 | 14 | 15 | 9 | 9+15=24→8 | Yes |
| 16 | 15 | 0 | 8 | 8+0=8 | Yes |
| 17 | 0 | 1 | 8 | 8+1=9 | Yes |
| 18 | 1 | 2 | 9 | 9+2=11 | Yes |
| 19 | 2 | 3 | 11 | 11+3=14 | Yes |
| 20 | 3 | 4 | 14 | 14+4=18→2 | Yes |
| 21 | 4 | 5 | 2 | 2+5=7 | Yes |
| 22 | 5 | 6 | 7 | 7+6=13 | Yes |
| 23 | 6 | 7 | 13 | 13+7=20→4 | Yes |
| 24 | 7 | 8 | 4 | 4+8=12 | Yes |
| 25 | 8 | 9 | 12 | 12+9=21→5 | Yes |
| 26 | 9 | 10 | 5 | 5+10=15 | Yes |
| 27 | 10 | 11 | 15 | 15+11=26→10 | Yes |
| 28 | 11 | 12 | 10 | 10+12=22→6 | Yes |
| 29 | 12 | 13 | 6 | 6+13=19→3 | Yes |
| 30 | 13 | 14 | 3 | 3+14=17→1 | Yes |
| 31 | 14 | 15 | 1 | 1+15=16→**0** | **No - HALT** |

## Mathematical Formulation

The recurrence relation is:
```
R0(n) = (R0(n-1) + R1(n)) mod 16
R1(n) = n mod 16
```

With initial conditions:
```
R0(0) = 0
R1(0) = 0
```

This gives us:
```
R0(n) = (R0(n-1) + n) mod 16
```

Expanding recursively:
```
R0(n) = (0 + 1 + 2 + 3 + ... + n) mod 16
R0(n) = (n(n+1)/2) mod 16
```

## Finding the Cycle Length

We need to find the smallest k > 0 such that:
```
R0(k) = 0
```

This means:
```
k(k+1)/2 ≡ 0 (mod 16)
```

Or equivalently:
```
k(k+1) ≡ 0 (mod 32)
```

Since k and (k+1) are consecutive integers, exactly one is even. For their product to be divisible by 32 = 2^5, we need the even one to be divisible by 32, or their product to contribute enough factors of 2.

## Systematic Search

Let's check triangular numbers modulo 16:

| k | k(k+1)/2 | mod 16 | Notes |
|---|----------|--------|-------|
| 1 | 1 | 1 | |
| 2 | 3 | 3 | |
| 3 | 6 | 6 | |
| 4 | 10 | 10 | |
| 5 | 15 | 15 | |
| 6 | 21 | 5 | |
| 7 | 28 | 12 | |
| 8 | 36 | 4 | |
| 9 | 45 | 13 | |
| 10 | 55 | 7 | |
| 11 | 66 | 2 | |
| 12 | 78 | 14 | |
| 13 | 91 | 11 | |
| 14 | 105 | 9 | |
| 15 | 120 | 8 | |
| 16 | 136 | 8 | k ≡ 0 (mod 16), sum repeats |
| 17 | 153 | 9 | |
| ... | ... | ... | |
| 31 | 496 | **0** | ✓ First zero! |

## Why k = 31?

The triangular number formula gives us:
```
T(31) = 31 × 32 / 2 = 496 = 31 × 16 = 0 (mod 16)
```

**Key insight:** 31 × 32 = 992, and 992 / 2 = 496 = 31 × 16

Since 496 is exactly divisible by 16, R0(31) = 0.

## Number Theory Perspective

We need k(k+1)/2 ≡ 0 (mod 16), which means k(k+1) ≡ 0 (mod 32).

The smallest k > 0 satisfying this:
- k = 31: 31 × 32 = 992 = 31 × 32 ✓

31 is special because:
- 31 = 2^5 - 1 (one less than 32)
- 32 = 2^5 (power of 2)
- Their product: 31 × 32 = 2^5 × (2^5 - 1) = 2^5(2^5 - 1)

Dividing by 2:
```
31 × 32 / 2 = 2^4 × (2^5 - 1) = 16 × 31 = 496 ≡ 0 (mod 16)
```

## Why Not Earlier?

For k < 31, we can verify that k(k+1)/2 is never divisible by 16:

**Key observation:** The sequence of triangular numbers mod 16 has period 32, and within the first period, only k=31 yields 0.

This can be proven by noting that:
- For k < 16: k and k+1 together contribute at most 4 factors of 2 (when k=15 or k=16)
- We need 5 factors of 2 total (from k(k+1)/2 ≡ 0 mod 16 → k(k+1) ≡ 0 mod 32)
- k=31 is the first value where 31×32/2 = 496, giving us exactly 16×31

## SUB Equivalence

The SUB operation (`[4, 2, 8, 15, 15]`) also produces 31 cycles because:

```
R0(n) = (R0(n-1) - n) mod 16
```

Expanding:
```
R0(n) = (0 - 1 - 2 - 3 - ... - n) mod 16
R0(n) = (-n(n+1)/2) mod 16
R0(n) = (16 - n(n+1)/2) mod 16  [when n(n+1)/2 < 16]
```

Since modular arithmetic treats -x ≡ 16-x (mod 16), the SUB sequence is the negative of the ADD sequence, but both reach zero at the same iteration count k=31.

## Conclusion

The ADD/SUB loop cycles exactly **31 times** because:

1. Each iteration adds the triangular sequence: 1, 2, 3, ..., n
2. R0 accumulates the sum: R0(n) = n(n+1)/2 mod 16
3. The first n where n(n+1)/2 ≡ 0 (mod 16) is n = 31
4. This is due to 31 × 32 / 2 = 496 = 31 × 16

The magic of 31 stems from it being 2^5 - 1, which when multiplied by 32 = 2^5 and divided by 2, yields a perfect multiple of 16.
