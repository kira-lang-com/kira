#include <metal_stdlib>
using namespace metal;
kernel void k(uint id [[thread_position_in_grid]]) {
    float2 v = float2(1, 2, 3);
}
