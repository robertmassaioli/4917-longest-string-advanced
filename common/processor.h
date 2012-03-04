#ifndef __4917_PROCESSOR_
#define __4917_PROCESSOR_

typedef unsigned char byte;

struct device {
	byte memory[16];
	byte R0, R1, PC;
};

/**
 * The purpose of this function is to run the program within a certain emulated processor step
 * timeout and return the number of characters that it would have ouput.
 */
int run_program(struct device* program, int timeout);
/**
 * The purpose of this function it to run the program with loop checking and return the number of
 * characters that the program would have output.
 */
int run_program_loop_check(struct device* program);

/**
 * Init an individual program
 */
int init_program(struct device* program);

/**
 * Perform a single logical step on a program and puts the value true in programFinished if the
 * program was finished in this step.
 */
int step_program(struct device* program, bool* programFinished);

/** 
 * This function copies all of the state from the src device to the dst device.
 */
void copy_program(struct device* dst, struct device* src);

/** 
 * This function compares the state of two devices and returns true if they are in exactly the same
 * state an false otherwise.
 */
bool compare_programs(struct device* one, struct device* two);

#endif
