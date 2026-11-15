#define _POSIX_C_SOURCE 200809L
#include "4917/machine.h"
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define SAMPLE_COUNT 5
#define INSTRUCTION_BATCH 65536
static volatile uint64_t sink;
static bool json_output;
static const char *instruction_names[16] = {
    "halt", "add-r0-r1", "sub-r0-r1", "inc-r0", "inc-r1", "dec-r0",
    "dec-r1", "nop", "output", "load-r0", "load-r1", "store-r0",
    "store-r1", "jump", "jump-if-zero", "jump-if-nonzero"
};
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
static bool run_instruction_case(unsigned opcode,int branch_taken){
    i4917_state *states=malloc(INSTRUCTION_BATCH*sizeof(*states));
    if(!states){fputs("unable to allocate instruction benchmark states\n",stderr);return false;}
    double times[SAMPLE_COUNT];uint64_t work=0;
    for(size_t sample=0;sample<SAMPLE_COUNT;sample++){
        for(size_t i=0;i<INSTRUCTION_BATCH;i++){
            i4917_state *s=&states[i];
            i4917_init(s,(uint8_t[]){0},1);
            s->memory[0]=(uint8_t)opcode;
            s->memory[1]=15;
            s->memory[15]=6;
            s->r0=(uint8_t)(i&15u);
            s->r1=(uint8_t)((i>>4)&15u);
            if(opcode==14)s->r0=(uint8_t)(branch_taken?0:1);
            if(opcode==15)s->r0=(uint8_t)(branch_taken?1:0);
            s->output_characters=(uint64_t)i;
        }
        uint64_t checksum=0;double start=now();
        for(size_t i=0;i<INSTRUCTION_BATCH;i++){
            i4917_event event;
            if(i4917_step(&states[i],&event)!=I4917_OK){free(states);fputs("instruction benchmark state failed validation\n",stderr);return false;}
            checksum+=(uint64_t)states[i].r0+states[i].r1+states[i].pc+
                      states[i].memory[15]+states[i].output_characters+
                      (event.emitted?(uint64_t)event.value:0u)+(event.halted?1u:0u);
        }
        times[sample]=now()-start;work=INSTRUCTION_BATCH;sink+=checksum;
    }
    char name[64];
    if(opcode==14||opcode==15)snprintf(name,sizeof(name),"instruction-%02u-%s-%s",opcode,instruction_names[opcode],branch_taken?"taken":"not-taken");
    else snprintf(name,sizeof(name),"instruction-%02u-%s",opcode,instruction_names[opcode]);
    report(name,INSTRUCTION_BATCH,work,"single_steps",times);
    free(states);return true;
}
static bool run_instruction_cases(int selected){
    if(selected>=0){
        if(selected==14||selected==15)return run_instruction_case((unsigned)selected,1)&&run_instruction_case((unsigned)selected,0);
        return run_instruction_case((unsigned)selected,1);
    }
    for(unsigned opcode=0;opcode<16;opcode++){
        if(opcode==14||opcode==15){if(!run_instruction_case(opcode,1)||!run_instruction_case(opcode,0))return false;}
        else if(!run_instruction_case(opcode,1))return false;
    }
    return true;
}
int main(int argc,char **argv){
    int selected_instruction=-1;bool instructions_only=false;
    for(int i=1;i<argc;i++){
        if(!strcmp(argv[i],"--json"))json_output=true;
        else if(!strcmp(argv[i],"--instructions"))instructions_only=true;
        else if(!strcmp(argv[i],"--instruction")&&i+1<argc){
            char *end=NULL;long value=strtol(argv[++i],&end,10);
            if(end==argv[i]||*end||value<0||value>15){fputs("--instruction requires an opcode from 0 through 15\n",stderr);return 2;}
            selected_instruction=(int)value;instructions_only=true;
        }else{fputs("usage: 4917-bench [--json] [--instructions | --instruction OPCODE]\n",stderr);return 2;}
    }
    if(instructions_only){
        if(!run_instruction_cases(selected_instruction))return 1;
        return sink==UINT64_MAX?1:0;
    }
    run_case("short-straight-line",(uint8_t[]){3,4,0},3,16,1000000);
    run_case("arithmetic-heavy",(uint8_t[]){3,4,1,5,6,2,13,0},8,128,500000);
    run_case("output-heavy",(uint8_t[]){8,15,8,10,8,9,0},7,32,500000);
    run_case("branch-loop",(uint8_t[]){3,15,0,3,13,0},6,256,250000);
    run_case("self-modifying",(uint8_t[]){3,11,5,13,2,0},6,64,500000);
    if(!run_instruction_cases(-1))return 1;
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
