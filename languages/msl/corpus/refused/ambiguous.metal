#include <metal_stdlib>
using namespace metal;
float f(float a, int b) { return a; }
float f(int a, float b) { return b; }
kernel void k(uint id [[thread_position_in_grid]]) {
    float x = f(1, 1);
}
