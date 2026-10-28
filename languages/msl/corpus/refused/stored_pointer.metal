#include <metal_stdlib>
using namespace metal;
struct S { device float* p; };
kernel void k(uint id [[thread_position_in_grid]]) {
    
}
