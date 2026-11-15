#include "4917/machine.h"
#include <errno.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void usage(FILE *f) {
    fputs("4917-c\n  run --program CSV [--max-steps N] [--json]\n  search --length N [--json]  (runs to halt or cycle)\n  step --memory CSV --r0 N --r1 N --pc N [--output-characters N] [--json]\n", f);
}
static bool number(const char *s, uint64_t *out) {
    if (!s || !*s || *s == '-') return false;
    errno = 0; char *end = NULL; unsigned long long n = strtoull(s, &end, 10);
    if (errno || end == s || *end) return false;
    *out = (uint64_t)n; return true;
}
static bool parse_csv(const char *csv, uint8_t p[16], size_t *len) {
    if (!csv || !*csv) return false;
    char *copy = malloc(strlen(csv) + 1); if (!copy) return false; strcpy(copy, csv);
    size_t n = 0; char *at = copy; bool ok = true;
    for (;;) {
        char *comma = strchr(at, ','); if (comma) *comma = '\0';
        uint64_t v;
        if (n == 16 || !number(at, &v) || v > 15) { ok = false; break; }
        p[n++] = (uint8_t)v;
        if (!comma) break;
        at = comma + 1;
    }
    free(copy); *len = n; return ok && n != 0;
}
static const char *term(i4917_termination t) {
    switch (t) { case I4917_HALTED: return "halted"; case I4917_LIMIT_REACHED: return "step_limit"; case I4917_CYCLE: return "cycle"; default: return "error"; }
}
static void state_json(const i4917_state *s) {
    printf("\"memory\":["); for (size_t i=0;i<16;i++) printf("%s%u",i?",":"",(unsigned)s->memory[i]);
    printf("],\"r0\":%u,\"r1\":%u,\"pc\":%u,\"output_characters\":\"%" PRIu64 "\"",(unsigned)s->r0,(unsigned)s->r1,(unsigned)s->pc,s->output_characters);
}
static int run_cmd(const char *csv, uint64_t limit, bool json) {
    uint8_t p[16]={0}; uint8_t *values=NULL; size_t len=0, nout=0, capacity=0;
    if (!parse_csv(csv,p,&len)) { fputs("invalid program: expected 1-16 comma-separated values from 0 through 15\n",stderr); return 2; }
    i4917_state s; i4917_init(&s,p,len); i4917_termination why=I4917_LIMIT_REACHED; uint64_t steps=0;
    for (;steps<limit;steps++) {
        i4917_event e; if (i4917_step(&s,&e)!=I4917_OK) { why=I4917_RUN_ERROR; break; }
        if (e.emitted) {
            if (nout==capacity) {
                size_t grown=capacity ? capacity*2 : 64;
                if (grown<capacity || grown>SIZE_MAX/sizeof(*values)) { why=I4917_RUN_ERROR; break; }
                uint8_t *next=realloc(values,grown);
                if (!next) { why=I4917_RUN_ERROR; break; }
                values=next;capacity=grown;
            }
            values[nout++]=e.value;
        }
        if (e.halted) { ++steps; why=I4917_HALTED; break; }
    }
    if (json) {
        printf("{\"schema\":\"4917-run-v1\",\"termination\":\"%s\",\"steps\":\"%" PRIu64 "\",\"output_values\":[",term(why),steps);
        for(size_t i=0;i<nout;i++) printf("%s%u",i?",":"",(unsigned)values[i]);
        printf("],"); state_json(&s); puts("}");
    } else {
        printf("termination: %s after %" PRIu64 " steps\noutput values:",term(why),steps);
        for(size_t i=0;i<nout;i++) printf(" %u",(unsigned)values[i]);
        printf("\noutput characters: %" PRIu64 "\n",s.output_characters);
    }
    free(values);
    return why==I4917_RUN_ERROR ? 1 : 0;
}
static int step_cmd(const char *csv,uint64_t r0,uint64_t r1,uint64_t pc,uint64_t output,bool json){
    uint8_t memory[16]={0};size_t length=0;
    if(!parse_csv(csv,memory,&length)||length!=16||r0>15||r1>15||pc>15){fputs("invalid state: memory must contain 16 nibbles and registers/PC must be 0 through 15\n",stderr);return 2;}
    i4917_state s;i4917_init(&s,memory,length);s.r0=(uint8_t)r0;s.r1=(uint8_t)r1;s.pc=(uint8_t)pc;s.output_characters=output;
    i4917_event e;i4917_error error=i4917_step(&s,&e);if(error!=I4917_OK){fputs("step failed\n",stderr);return 1;}
    if(json){printf("{\"schema\":\"4917-step-v1\",\"event_value\":");if(e.emitted)printf("%u",(unsigned)e.value);else fputs("null",stdout);
        printf(",\"halted\":%s,",e.halted?"true":"false");state_json(&s);puts("}");}
    else{printf("event: %s",e.emitted?"output":"none");if(e.emitted)printf(" %u",(unsigned)e.value);printf("\nhalted: %s\n",e.halted?"yes":"no");}
    return 0;
}
static int search_cmd(uint64_t length,bool json) {
    if(length<1||length>5){fputs("search length must be from 1 through 5\n",stderr);return 2;}
    uint64_t total=1;for(uint64_t i=0;i<length;i++)total*=16;
    uint64_t halted=0,cycled=0,errors=0,best=0,winners=0;uint8_t first[16]={0};
    for(uint64_t id=0;id<total;id++){
        uint64_t x=id;uint8_t p[16]={0};for(uint64_t j=length;j>0;j--){p[j-1]=(uint8_t)(x&15u);x>>=4;}
        i4917_state s;i4917_init(&s,p,(size_t)length);i4917_run_result r=i4917_run_until_halt_or_cycle(&s);
        if(r.termination==I4917_HALTED){halted++;if(!winners||r.output_characters>best){best=r.output_characters;winners=1;memcpy(first,p,16);}else if(r.output_characters==best)winners++;}
        else if(r.termination==I4917_CYCLE)cycled++;
        else errors++;
    }
    if(json){
        printf("{\"schema\":\"4917-search-v2\",\"length\":%" PRIu64 ",\"candidate_count\":\"%" PRIu64 "\",\"halted\":\"%" PRIu64 "\",\"cycled\":\"%" PRIu64 "\",\"errors\":\"%" PRIu64 "\",\"exhaustive\":%s,\"best_output_characters\":\"%" PRIu64 "\",\"winner_count\":\"%" PRIu64 "\",\"first_winner\":[",length,total,halted,cycled,errors,errors?"false":"true",best,winners);
        for(uint64_t i=0;i<length;i++)printf("%s%u",i?",":"",(unsigned)first[i]);puts("]}");
    }else printf("candidates: %" PRIu64 "\nhalted: %" PRIu64 "\ncycled: %" PRIu64 "\nerrors: %" PRIu64 "\nexhaustive: %s\nbest output characters: %" PRIu64 "\nwinner count: %" PRIu64 "\n",total,halted,cycled,errors,errors?"no":"yes",best,winners);
    return 0;
}
int main(int argc,char **argv){
    if(argc<2||!strcmp(argv[1],"--help")||!strcmp(argv[1],"-h")){usage(stdout);return argc<2?2:0;}
    bool run=!strcmp(argv[1],"run"),search=!strcmp(argv[1],"search"),step=!strcmp(argv[1],"step"),json=false;
    if(!run&&!search&&!step){usage(stderr);return 2;}
    const char *program=NULL,*memory=NULL;uint64_t length=0,limit=10000,r0=0,r1=0,pc=0,output=0;bool max_steps_set=false;
    for(int i=2;i<argc;i++){
        if(!strcmp(argv[i],"--json"))json=true;
        else if(i+1<argc&&!strcmp(argv[i],"--program"))program=argv[++i];
        else if(i+1<argc&&!strcmp(argv[i],"--memory"))memory=argv[++i];
        else if(i+1<argc&&!strcmp(argv[i],"--length")){if(!number(argv[++i],&length))return 2;}
        else if(i+1<argc&&!strcmp(argv[i],"--max-steps")){if(!number(argv[++i],&limit))return 2;max_steps_set=true;}
        else if(i+1<argc&&!strcmp(argv[i],"--r0")){if(!number(argv[++i],&r0))return 2;}
        else if(i+1<argc&&!strcmp(argv[i],"--r1")){if(!number(argv[++i],&r1))return 2;}
        else if(i+1<argc&&!strcmp(argv[i],"--pc")){if(!number(argv[++i],&pc))return 2;}
        else if(i+1<argc&&!strcmp(argv[i],"--output-characters")){if(!number(argv[++i],&output))return 2;}
        else{usage(stderr);return 2;}
    }
    if(run){if(!program){usage(stderr);return 2;}return run_cmd(program,limit,json);}
    if(step){if(!memory){usage(stderr);return 2;}return step_cmd(memory,r0,r1,pc,output,json);}
    if(max_steps_set){fputs("search runs until halt or cycle; --max-steps is only available for run\n",stderr);return 2;}
    return search_cmd(length,json);
}
