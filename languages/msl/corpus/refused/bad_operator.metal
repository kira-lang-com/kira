#include <metal_stdlib>
using namespace metal;
kernel void k(uint id [[thread_position_in_grid]]) {
    float x = 1.5 % 2.0;
}
