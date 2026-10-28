/*
 * The C side of the seam forms kira's fixture does not reach: unions, target
 * width aliases, variadic calls, owned pointers and bit-fields. No system
 * headers, like ffi_fixture.h, so it builds the same for every target.
 */
#ifndef KLF_SEAM_H
#define KLF_SEAM_H

/* A union read back by its member: the bytes one member wrote, read as
 * another, prove the members share storage. */
union seam_word {
    unsigned int bits;
    float value;
    unsigned char bytes[4];
};
union seam_word seam_word_of_float(float value);
unsigned int seam_word_bits(union seam_word word);
float seam_word_value(const union seam_word *word);

/* A struct holding a union beside a tag, the shape event records take. */
struct seam_tagged {
    int tag;
    union seam_word word;
};
long long seam_tagged_sum(struct seam_tagged tagged);

/* `unsigned long long` and `long long` are the widths `@FFI.Alias` names;
 * plain `long` is 32 bits on Windows. */
unsigned long long seam_ulong_twice(unsigned long long value);
long long seam_long_negate(long long value);

/* A handle C allocates and the importer frees: `seam_box_free` counts the
 * frees, so a handle freed twice or never shows in the count. */
struct seam_box {
    int value;
    int live;
};
struct seam_box *seam_box_new(int value);
int seam_box_value(const struct seam_box *box);
void seam_box_free(struct seam_box *box);
int seam_box_frees(void);
int seam_box_live(void);

/* A variadic function: `kinds` names each argument after it, `i` an int,
 * `l` a long long, `d` a double (counted in tenths), `s` a string (its length)
 * and `p` a pointer (1 when not null). */
long long seam_tally(const char *kinds, ...);

/* Callbacks: `seam_each` calls `visit` with each value and the `data` it was
 * handed, and sums what it returns; `seam_apply` calls `unary` once. */
typedef int (*seam_visit)(int value, void *data);
int seam_each(const int *values, int count, seam_visit visit, void *data);
typedef int (*seam_unary)(int value);
int seam_apply(seam_unary unary, int value);

/* Bit-fields: runs that share a unit, one pushed to the next unit, signed
 * ones, and ordinary members between them. */
struct seam_flags {
    unsigned char tag;
    unsigned int mode : 3;
    int delta : 5;
    unsigned int wide : 20;
    unsigned char after;
    unsigned long long big : 40;
    short tail : 7;
};
int seam_flags_size(void);
long long seam_flags_sum(struct seam_flags flags);
struct seam_flags seam_flags_make(int seed);
long long seam_flags_at(const struct seam_flags *flags);

#endif
