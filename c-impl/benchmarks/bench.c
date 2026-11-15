#define _POSIX_C_SOURCE 200809L
#include "4917/machine.h"
#include <inttypes.h>
#include <stdio.h>
#include <time.h>

static volatile uint64_t sink;
static double now(void){struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return (double)t.tv_sec+(double)t.tv_nsec/1e9;}
static void run_case(const char *name,const uint8_t *program,size_t length,uint64_t limit,uint64_t repetitions){
    i4917_state initial;i4917_init(&initial,program,length);uint64_t instructions=0;double start=now();
    for(uint64_t i=0;i<repetitions;i++){i4917_run_result r=i4917_run_bounded(&initial,limit);instructions+=r.steps;sink+=r.output_characters+(uint64_t)r.final_state.pc;}
    double seconds=now()-start;printf("%s: repetitions=%" PRIu64 " instructions=%" PRIu64 " seconds=%.6f instructions_per_second=%.0f sink=%" PRIu64 "\n",name,repetitions,instructions,seconds,seconds?instructions/seconds:0.0,sink);
}
int main(void){
    run_case("short-straight-line",(uint8_t[]){3,4,0},3,16,1000000);
    run_case("arithmetic-heavy",(uint8_t[]){3,4,1,5,6,2,13,0},8,128,500000);
    run_case("output-heavy",(uint8_t[]){8,15,8,10,8,9,0},7,32,500000);
    run_case("branch-loop",(uint8_t[]){3,15,0,3,13,0},6,256,250000);
    run_case("self-modifying",(uint8_t[]){3,11,5,13,2,0},6,64,500000);
    i4917_state looping;i4917_init(&looping,(uint8_t[]){8,1,13,0},4);
    double cycle_start=now();uint64_t cycle_steps=0;
    for(uint64_t i=0;i<250000;i++){i4917_run_result r=i4917_run_until_halt_or_cycle(&looping);cycle_steps+=r.steps;sink+=r.output_characters;}
    double cycle_seconds=now()-cycle_start;
    printf("output-cycle-detection: repetitions=250000 logical_steps=%" PRIu64 " seconds=%.6f steps_per_second=%.0f sink=%" PRIu64 "\n",cycle_steps,cycle_seconds,cycle_steps/cycle_seconds,sink);
    /* Small exact search workload: enumerate all two-cell programs. */
    double start=now();uint64_t candidates=0,completed=0,checksum=0;
    for(unsigned id=0;id<256;id++){uint8_t p[2]={(uint8_t)(id>>4),(uint8_t)(id&15)};i4917_state s;i4917_init(&s,p,2);i4917_run_result r=i4917_run_bounded(&s,128);candidates++;completed+=r.termination==I4917_HALTED;checksum+=r.output_characters;}
    double seconds=now()-start;printf("search-length-2: candidates=%" PRIu64 " completed=%" PRIu64 " seconds=%.6f candidates_per_second=%.0f checksum=%" PRIu64 "\n",candidates,completed,seconds,candidates/seconds,checksum);
    return sink==UINT64_MAX?1:0;
}
