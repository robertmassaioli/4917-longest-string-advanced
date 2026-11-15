#define _POSIX_C_SOURCE 200809L
#include "4917/machine.h"
#include <inttypes.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

#define SAMPLE_COUNT 5
static volatile uint64_t sink;
static bool json_output;
static double now(void){struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return (double)t.tv_sec+(double)t.tv_nsec/1e9;}
static void report(const char *name,uint64_t repetitions,uint64_t work_per_sample,const char *unit,const double times[SAMPLE_COUNT]){
    double rates[SAMPLE_COUNT];for(size_t i=0;i<SAMPLE_COUNT;i++)rates[i]=(double)work_per_sample/times[i];
    for(size_t i=0;i<SAMPLE_COUNT;i++)for(size_t j=i+1;j<SAMPLE_COUNT;j++)if(rates[j]<rates[i]){double t=rates[i];rates[i]=rates[j];rates[j]=t;}
    if(json_output)printf("{\"fixture\":\"%s\",\"samples\":%d,\"repetitions_per_sample\":%" PRIu64 ",\"work_per_sample\":%" PRIu64 ",\"work_unit\":\"%s\",\"throughput_per_second_min\":%.3f,\"throughput_per_second_median\":%.3f,\"throughput_per_second_max\":%.3f}\n",name,SAMPLE_COUNT,repetitions,work_per_sample,unit,rates[0],rates[SAMPLE_COUNT/2],rates[SAMPLE_COUNT-1]);
    else printf("%s: samples=%d repetitions_per_sample=%" PRIu64 " %s_per_sample=%" PRIu64 " throughput_%s_per_second_min/median/max=%.0f/%.0f/%.0f sink=%" PRIu64 "\n",name,SAMPLE_COUNT,repetitions,unit,work_per_sample,unit,rates[0],rates[SAMPLE_COUNT/2],rates[SAMPLE_COUNT-1],sink);
}
static void run_case(const char *name,const uint8_t *program,size_t length,uint64_t limit,uint64_t repetitions){
    i4917_state initial;i4917_init(&initial,program,length);double times[SAMPLE_COUNT];uint64_t work=0;
    for(size_t sample=0;sample<SAMPLE_COUNT;sample++){uint64_t instructions=0;double start=now();
        for(uint64_t i=0;i<repetitions;i++){i4917_run_result r=i4917_run_bounded(&initial,limit);instructions+=r.steps;sink+=r.output_characters+(uint64_t)r.final_state.pc;}
        times[sample]=now()-start;work=instructions;
    }
    report(name,repetitions,work,"instructions",times);
}
int main(int argc,char **argv){
    if(argc==2&&!strcmp(argv[1],"--json"))json_output=true;else if(argc!=1){fputs("usage: 4917-bench [--json]\n",stderr);return 2;}
    run_case("short-straight-line",(uint8_t[]){3,4,0},3,16,1000000);
    run_case("arithmetic-heavy",(uint8_t[]){3,4,1,5,6,2,13,0},8,128,500000);
    run_case("output-heavy",(uint8_t[]){8,15,8,10,8,9,0},7,32,500000);
    run_case("branch-loop",(uint8_t[]){3,15,0,3,13,0},6,256,250000);
    run_case("self-modifying",(uint8_t[]){3,11,5,13,2,0},6,64,500000);
    i4917_state looping;i4917_init(&looping,(uint8_t[]){8,1,13,0},4);double cycle_times[SAMPLE_COUNT];uint64_t cycle_work=0;
    for(size_t sample=0;sample<SAMPLE_COUNT;sample++){uint64_t steps=0;double start=now();
        for(uint64_t i=0;i<250000;i++){i4917_run_result r=i4917_run_until_halt_or_cycle(&looping);steps+=r.steps;sink+=r.output_characters;}
        cycle_times[sample]=now()-start;cycle_work=steps;
    }
    report("output-cycle-detection",250000,cycle_work,"logical_steps",cycle_times);
    double search_times[SAMPLE_COUNT];uint64_t search_work=0,completed=0,checksum=0;
    for(size_t sample=0;sample<SAMPLE_COUNT;sample++){uint64_t candidates=0,done=0,sum=0;double start=now();
        for(unsigned id=0;id<256;id++){uint8_t p[2]={(uint8_t)(id>>4),(uint8_t)(id&15)};i4917_state s;i4917_init(&s,p,2);i4917_run_result r=i4917_run_bounded(&s,128);candidates++;done+=r.termination==I4917_HALTED;sum+=r.output_characters;}
        search_times[sample]=now()-start;search_work=candidates;completed=done;checksum=sum;
    }
    report("search-length-2",1,search_work,"candidates",search_times);
    if(!json_output)printf("search completed=%" PRIu64 " unresolved=%" PRIu64 " checksum=%" PRIu64 "\n",completed,search_work-completed,checksum);
    return sink==UINT64_MAX?1:0;
}
