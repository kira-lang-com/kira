#include <metal_stdlib>
using namespace metal;
float f() {
    threadgroup float shared[4];
    return shared[0];
}
kernel void k(uint id [[thread_position_in_grid]]) {
    float x = f();
}
