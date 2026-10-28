#include <metal_stdlib>
using namespace metal;
constant bool on [[function_constant(0)]];
kernel void k(device float* data [[buffer(0), function_constant(on)]]) {}
