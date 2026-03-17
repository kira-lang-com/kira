#include "hello_ffi.h"

void hk_setup(const hk_color* color) {
    (void)color;
}

hk_buffer hk_make_buffer(const hk_buffer* desc) {
    if (desc) {
        return *desc;
    }
    hk_buffer b;
    b.id = 0;
    return b;
}

void hk_draw(int base_element, int num_elements, int num_instances) {
    (void)base_element;
    (void)num_elements;
    (void)num_instances;
}

int hk_add(int a, int b) {
    return a + b;
}

float hk_mul(float a, float b) {
    return a * b;
}

float hk_square(float x) {
    return x * x;
}

