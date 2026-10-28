#include <metal_stdlib>
using namespace metal;
vertex float4 v() { return float4(0); }
fragment float4 f() { return float4(1); }
kernel void k(uint id [[thread_position_in_grid]]) {
    
}
