#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct hk_color {
    float r, g, b, a;
} hk_color;

typedef struct hk_buffer {
    uint32_t id;
} hk_buffer;

typedef void* hk_context;

typedef void (*hk_callback)(int value);

void hk_setup(const hk_color* color);

hk_buffer hk_make_buffer(const hk_buffer* desc);

void hk_draw(int base_element, int num_elements, int num_instances);

// Struct-by-value example
hk_color hk_color_add(hk_color a, hk_color b);

// Callback example (function pointer)
void hk_invoke_callback(void (*cb)(int), int value);

// --- Dumb math functions ---

// Adds two integers
int hk_add(int a, int b);

// Multiplies two floats
float hk_mul(float a, float b);

// Returns the square of a number
float hk_square(float x);

#ifdef __cplusplus
} // extern "C"
#endif
