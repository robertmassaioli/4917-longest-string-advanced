I'm expecting to be able to take a Program, and a the results of the execution of a program and be able to do things like:

 1. Mark all of the memory locations that were not used for any reason in the program as wildcards.
 2. Wildcard print operations by wether or not the consistently output one character, two characters or a mix of both.
 3. If simple variables like R1 or R0 could be swapped out in the program, a way to represent that if you did a wholesale swap from R0 operations to R1 operations everything would still work the same.

What are other ways in which we might spot that two programs are ultimately the same.

## Examples

## Unused Memory Location Wildcarding

Example One: Start with Halt

`[0, 8, 15, 14]`

This program will always halt immediately. So it is functionally equivalent to all of the programs that have the format `[0, *, *, *, ...]`

Example Two: Manipulating vs Using R0 and R1
`[8, 15, 1, 8, 15]` 

This program will just print out 15 twice. If the command 1 was replaced with any command from 1-6, that would not change the behaviour of the program at all because the values R0 and R1 are not used to do anything.

Therefore I have a statement instructions 1-6 don't actually do anything UNLESS the program at some point also executes one of the 11, 12, 14, 15 instructions are used.

Even the 9 and 10 instructions only set the values in R0 and R1 but, if they are not used by the 11,12,14,15 then they can't impact the project as a whole.

All instructions that modify R0 or R1 but never "use" R0 or R1 are functionally operate as though they were the same as instruction 7 NOP.

Example 3: Swapping equivalent R0 and R1 commands

For some programs, using R0 and R1 could be interchangible so long as all of the operations that relate to registered are toggled between r0 and r1 as is appropriate.