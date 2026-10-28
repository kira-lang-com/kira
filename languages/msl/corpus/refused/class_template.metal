#include <metal_stdlib>
using namespace metal;
template <int N> float f() { return N; }
kernel void k(uint id [[thread_position_in_grid]]) {
    
}
