#include "klfseam.h"
#include <stdarg.h>
#include <string.h>

union seam_word seam_word_of_float(float value) {
    union seam_word word;
    word.value = value;
    return word;
}

unsigned int seam_word_bits(union seam_word word) {
    return word.bits;
}

float seam_word_value(const union seam_word *word) {
    return word->value;
}

long long seam_tagged_sum(struct seam_tagged tagged) {
    return (long long)tagged.tag + (long long)tagged.word.bits;
}

unsigned long long seam_ulong_twice(unsigned long long value) {
    return value * 2;
}

long long seam_long_negate(long long value) {
    return -value;
}

static struct seam_box seam_boxes[16];
static int seam_box_next = 0;
static int seam_box_freed = 0;

struct seam_box *seam_box_new(int value) {
    struct seam_box *box = &seam_boxes[seam_box_next % 16];
    seam_box_next += 1;
    box->value = value;
    box->live = 1;
    return box;
}

int seam_box_value(const struct seam_box *box) {
    return box->live ? box->value : -1;
}

void seam_box_free(struct seam_box *box) {
    box->live = 0;
    seam_box_freed += 1;
}

int seam_box_frees(void) {
    return seam_box_freed;
}

int seam_box_live(void) {
    int live = 0;
    for (int index = 0; index < 16; index += 1) {
        live += seam_boxes[index].live;
    }
    return live;
}

long long seam_tally(const char *kinds, ...) {
    va_list arguments;
    long long total = 0;
    va_start(arguments, kinds);
    for (const char *kind = kinds; *kind != 0; kind += 1) {
        switch (*kind) {
        case 'i': total += va_arg(arguments, int); break;
        case 'l': total += va_arg(arguments, long long); break;
        case 'd': total += (long long)(va_arg(arguments, double) * 10.0); break;
        case 's': total += (long long)strlen(va_arg(arguments, const char *)); break;
        case 'p': total += va_arg(arguments, void *) != 0; break;
        default: total -= 1000; break;
        }
    }
    va_end(arguments);
    return total;
}

int seam_each(const int *values, int count, seam_visit visit, void *data) {
    int total = 0;
    for (int index = 0; index < count; index += 1) {
        total += visit(values[index], data);
    }
    return total;
}

int seam_apply(seam_unary unary, int value) {
    return unary(value);
}

int seam_flags_size(void) {
    return (int)sizeof(struct seam_flags);
}

long long seam_flags_sum(struct seam_flags flags) {
    return flags.tag + flags.mode * 10LL + flags.delta * 100LL + flags.wide * 1000LL
        + flags.after * 7LL + (long long)flags.big * 3 + flags.tail * 11LL;
}

struct seam_flags seam_flags_make(int seed) {
    struct seam_flags flags;
    flags.tag = (unsigned char)seed;
    flags.mode = 5;
    flags.delta = -seed;
    flags.wide = 1000000;
    flags.after = 200;
    flags.big = 1099511627775ULL;
    flags.tail = -64;
    return flags;
}

long long seam_flags_at(const struct seam_flags *flags) {
    return seam_flags_sum(*flags);
}
