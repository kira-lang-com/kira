#include <metal_stdlib>
using namespace metal;
uint down(uint n) { return n == 0 ? 0 : down(n - 1); }
kernel void k(uint id [[thread_position_in_grid]]) {
    uint x = down(id);
}
