#include "4917/machine.h"
#include "argtable3.h"
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void usage(FILE *f) {
    fputs("Usage: 4917-c <command> [options]\n\n"
          "Commands:\n"
          "  run      Execute a program\n"
          "  search   Exhaustively search programs of a given length\n"
          "  step     Execute one instruction from a supplied state\n\n"
          "Run '4917-c <command> --help' for command options.\n", f);
}

static void command_usage(FILE *f, const char *command, void **table,
                          const char *description) {
    fprintf(f, "Usage: 4917-c %s", command);
    arg_print_syntax(f, table, "\n");
    fprintf(f, "%s\n\nOptions:\n", description);
    arg_print_glossary(f, table, "  %-28s %s\n");
}

static bool number(const char *s, uint64_t *out) {
    if (!s || !*s) return false;
    uint64_t value = 0;
    for (const unsigned char *at = (const unsigned char *)s; *at; ++at) {
        if (*at < '0' || *at > '9') return false;
        uint64_t digit = (uint64_t)(*at - '0');
        if (value > (UINT64_MAX - digit) / 10) return false;
        value = value * 10 + digit;
    }
    *out = value;
    return true;
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
static int search_cmd(uint64_t length,uint64_t limit,bool json) {
    if(length<1||length>4){fputs("search length must be from 1 through 4\n",stderr);return 2;}
    uint64_t total=1;for(uint64_t i=0;i<length;i++)total*=16;
    uint64_t completed=0,unresolved=0,best=0,winners=0;uint8_t first[16]={0};
    for(uint64_t id=0;id<total;id++){
        uint64_t x=id;uint8_t p[16]={0};for(uint64_t j=length;j>0;j--){p[j-1]=(uint8_t)(x&15u);x>>=4;}
        i4917_state s;i4917_init(&s,p,(size_t)length);i4917_run_result r=i4917_run_bounded(&s,limit);
        if(r.termination==I4917_HALTED){completed++;if(!winners||r.output_characters>best){best=r.output_characters;winners=1;memcpy(first,p,16);}else if(r.output_characters==best)winners++;}else unresolved++;
    }
    if(json){
        printf("{\"schema\":\"4917-search-v1\",\"length\":%" PRIu64 ",\"candidate_count\":\"%" PRIu64 "\",\"completed\":\"%" PRIu64 "\",\"unresolved\":\"%" PRIu64 "\",\"exhaustive\":%s,\"best_output_characters\":\"%" PRIu64 "\",\"winner_count\":\"%" PRIu64 "\",\"first_winner\":[",length,total,completed,unresolved,unresolved?"false":"true",best,winners);
        for(uint64_t i=0;i<length;i++)printf("%s%u",i?",":"",(unsigned)first[i]);puts("]}");
    }else printf("candidates: %" PRIu64 "\ncompleted: %" PRIu64 "\nunresolved: %" PRIu64 "\nexhaustive: %s\nbest output characters: %" PRIu64 "\nwinner count: %" PRIu64 "\n",total,completed,unresolved,unresolved?"no":"yes",best,winners);
    return 0;
}
static int parse_error(const char *command, struct arg_end *end,
                       void **table) {
    arg_print_errors(stderr, end, command);
    fputs("Try '4917-c ", stderr);
    fputs(command, stderr);
    fputs(" --help' for more information.\n", stderr);
    command_usage(stderr, command, table, "");
    return 2;
}

static int invalid_number(const char *command, const char *option,
                          const char *value, void **table) {
    fprintf(stderr, "4917-c %s: invalid nonnegative decimal value for %s: '%s'\n",
            command, option, value ? value : "");
    command_usage(stderr, command, table, "");
    return 2;
}

int main(int argc, char **argv) {
    if (argc < 2) {
        usage(stderr);
        return 2;
    }
    if (!strcmp(argv[1], "--help") || !strcmp(argv[1], "-h")) {
        usage(stdout);
        return 0;
    }

    const char *command = argv[1];
    bool run = !strcmp(command, "run");
    bool search = !strcmp(command, "search");
    bool step = !strcmp(command, "step");
    if (!run && !search && !step) {
        fprintf(stderr, "4917-c: unknown command '%s'\n", command);
        usage(stderr);
        return 2;
    }

    struct arg_str *program_arg = NULL;
    struct arg_str *memory_arg = NULL;
    struct arg_str *length_arg = NULL;
    struct arg_str *max_steps_arg = NULL;
    struct arg_str *r0_arg = NULL;
    struct arg_str *r1_arg = NULL;
    struct arg_str *pc_arg = NULL;
    struct arg_str *output_arg = NULL;
    struct arg_lit *json_arg = NULL;
    struct arg_lit *help_arg = arg_lit0("h", "help", "Print this help and exit");
    struct arg_end *end = arg_end(20);
    void *table[10];
    size_t table_size = 0;

    if (run) {
        program_arg = arg_str1(NULL, "program", "CSV", "Program values (1-16 nibbles)");
        max_steps_arg = arg_str0(NULL, "max-steps", "N", "Stop after at most N instructions (default: 10000)");
        json_arg = arg_lit0(NULL, "json", "Write machine-readable JSON");
        table[table_size++] = program_arg;
        table[table_size++] = max_steps_arg;
        table[table_size++] = json_arg;
    } else if (search) {
        length_arg = arg_str1(NULL, "length", "N", "Program length (1-4)");
        max_steps_arg = arg_str0(NULL, "max-steps", "N", "Stop each candidate after at most N instructions (default: 10000)");
        json_arg = arg_lit0(NULL, "json", "Write machine-readable JSON");
        table[table_size++] = length_arg;
        table[table_size++] = max_steps_arg;
        table[table_size++] = json_arg;
    } else {
        memory_arg = arg_str1(NULL, "memory", "CSV", "Exactly 16 memory nibbles");
        r0_arg = arg_str0(NULL, "r0", "N", "Initial r0 value (default: 0)");
        r1_arg = arg_str0(NULL, "r1", "N", "Initial r1 value (default: 0)");
        pc_arg = arg_str0(NULL, "pc", "N", "Initial program counter (default: 0)");
        output_arg = arg_str0(NULL, "output-characters", "N", "Initial output-character count (default: 0)");
        json_arg = arg_lit0(NULL, "json", "Write machine-readable JSON");
        table[table_size++] = memory_arg;
        table[table_size++] = r0_arg;
        table[table_size++] = r1_arg;
        table[table_size++] = pc_arg;
        table[table_size++] = output_arg;
        table[table_size++] = json_arg;
    }
    table[table_size++] = help_arg;
    table[table_size++] = end;

    if (arg_nullcheck(table) != 0) {
        fputs("4917-c: unable to allocate command-line parser state\n", stderr);
        arg_freetable(table, table_size);
        return 1;
    }

    int errors = arg_parse(argc - 1, argv + 1, table);
    if (help_arg->count > 0) {
        command_usage(stdout, command, table,
                      run ? "Execute a program." :
                      search ? "Exhaustively search programs of a given length." :
                               "Execute one instruction from a supplied state.");
        arg_freetable(table, table_size);
        return 0;
    }
    if (errors > 0) {
        int result = parse_error(command, end, table);
        arg_freetable(table, table_size);
        return result;
    }

    uint64_t limit = 10000;
    uint64_t value = 0;
    if (max_steps_arg && max_steps_arg->count > 0) {
        if (!number(max_steps_arg->sval[0], &limit)) {
            int result = invalid_number(command, "--max-steps",
                                        max_steps_arg->sval[0], table);
            arg_freetable(table, table_size);
            return result;
        }
    }
    bool json = json_arg->count > 0;
    int result;

    if (run) {
        result = run_cmd(program_arg->sval[0], limit, json);
    } else if (search) {
        if (!number(length_arg->sval[0], &value)) {
            result = invalid_number(command, "--length", length_arg->sval[0], table);
        } else if (value < 1 || value > 4) {
            fprintf(stderr, "4917-c search: length must be from 1 through 4 (got '%s')\n",
                    length_arg->sval[0]);
            command_usage(stderr, command, table, "");
            result = 2;
        } else {
            result = search_cmd(value, limit, json);
        }
    } else {
        uint64_t r0 = 0, r1 = 0, pc = 0, output = 0;
        struct {
            struct arg_str *argument;
            const char *name;
            uint64_t *value;
        } numbers[] = {
            {r0_arg, "--r0", &r0},
            {r1_arg, "--r1", &r1},
            {pc_arg, "--pc", &pc},
            {output_arg, "--output-characters", &output}
        };
        result = 0;
        for (size_t i = 0; i < sizeof(numbers) / sizeof(numbers[0]); ++i) {
            if (numbers[i].argument->count > 0 &&
                !number(numbers[i].argument->sval[0], numbers[i].value)) {
                result = invalid_number(command, numbers[i].name,
                                        numbers[i].argument->sval[0], table);
                break;
            }
        }
        if (result == 0 && (r0 > 15 || r1 > 15 || pc > 15)) {
            const char *option = r0 > 15 ? "--r0" : r1 > 15 ? "--r1" : "--pc";
            fprintf(stderr, "4917-c step: %s must be from 0 through 15\n", option);
            command_usage(stderr, command, table, "");
            result = 2;
        }
        if (result == 0) {
            result = step_cmd(memory_arg->sval[0], r0, r1, pc, output, json);
        }
    }

    arg_freetable(table, table_size);
    return result;
}
