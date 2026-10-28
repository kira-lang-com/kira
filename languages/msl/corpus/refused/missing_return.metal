#include <metal_stdlib>
using namespace metal;
float f(float x) { if (x > 0) { return x; } }
kernel void k(uint id [[thread_position_in_grid]]) {
    
}
