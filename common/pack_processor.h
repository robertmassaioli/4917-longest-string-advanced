#ifndef __4917_PACK_PROCESSOR
#define __4917_PACK_PROCESSOR

#include <stdint.h>
#include "processor.h"

/**
 * Pack the first half of a device into 32 bits.
 */
void pack_half_device(uint32_t* to, struct device* from);

/**
 * Unpack the 32 bits of data into the first half of the memory
 * of a device.
 */
void unpack_half_device(struct device* to, uint32_t from);

/**
 * Packs an entire device into 64 bits.
 */
void pack_device(uint64_t* to, struct device* from);

/**
 * Unpacks 64 bits of data into the memory of a device
 */
void unpack_device(struct device* to, uint64_t from);

#endif
