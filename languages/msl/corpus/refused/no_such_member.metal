#include <metal_stdlib>
using namespace metal;
struct S { float x; };
kernel void k(uint id [[thread_position_in_grid]]) {
    S s = {};
    float y = s.y;
}
