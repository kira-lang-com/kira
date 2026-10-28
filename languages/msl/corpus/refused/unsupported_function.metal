#include <metal_stdlib>
using namespace metal;
kernel void k(uint id [[thread_position_in_grid]]) {
    float x = exp10(2.0);
}
