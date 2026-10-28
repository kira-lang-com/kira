#include <metal_stdlib>
using namespace metal;
template <typename T> T zero() { return T(0); }
kernel void k(uint id [[thread_position_in_grid]]) {
    float x = zero();
}
