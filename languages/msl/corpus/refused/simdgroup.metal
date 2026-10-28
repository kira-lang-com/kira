#include <metal_stdlib>
using namespace metal;
kernel void k(uint lane [[thread_index_in_simdgroup]]) {}
