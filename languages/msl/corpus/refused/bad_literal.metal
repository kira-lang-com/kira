#include <metal_stdlib>
using namespace metal;
kernel void k(uint id [[thread_position_in_grid]]) {
    int x = 99999999999;
}
