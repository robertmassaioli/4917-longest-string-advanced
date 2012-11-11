/** 
 * @file processor.h 
 * \brief This header defines the operations the ways that you can emulate a 4917 machine.
 */

#ifndef __4917_PROCESSOR_
#define __4917_PROCESSOR_

/** An unsigned char can be a byte right? */
typedef unsigned char byte;

/**
 * This struct represents the internals of a 4917 machine.
 */
struct device {
	byte memory[16];
	byte R0, R1, PC;
};

// TODO run_program should return a long and not an int. Be prepared for anything.
/**
 * Run the emulator until the timeout (in steps) has been reached.
 *
 * \param program The program to run through. It should be provided in its initial state.
 * \param timeout The number of steps to let the program run through before we stop and
 * assume unsuccessful.
 * \return The number of characters that it printed to the 'screen' and 0 if it timed out.
 */
int run_program(struct device* program, int timeout);

/**
 * Attempt to run the program and finish when the program does or if an infinite loop is
 * spotted.
 * 
 * This function promises not to make any edits to the program that is passed in. 
 *
 * \param program The program to be run through.
 * \return The number of characters that the program printed to the 'screen' and 0 if it
 * had an infinite loop.
 */
int run_program_loop_check(struct device* program);

/**
 * Init an individual program.
 *
 * \param program Sets this program to a valid initial state.
 */
int init_program(struct device* program);

/**
 * Perform a single logical step on a program.
 *
 * \param program This program will be one instruction further in its instruction cycle at
 * the end of this step.
 * \param programFinished This is set to true if the program ended on this step. It is
 * unchanged otherwise.
 * \return The number of characters printed to the screen in this step.
 */
int step_program(struct device* program, bool* programFinished);

/** 
 * This function copies all of the state from the src device to the dst device.
 * \param dst The device to copy to.
 * \param src The device to copy from.
 */
void copy_program(struct device* dst, struct device* src);

/** 
 * Compare the state of two programs.
 * \param one Program One
 * \param two Program Two
 * \return True, if the state of Program One is identical to the state of Program Two.
 * False otherwise.
 */
bool compare_programs(struct device* one, struct device* two);

/**
 * Given a program it gives you the length of that program.
 *
 * \param program The program to find the length of.
 */
int program_length(struct device* program);

#endif
