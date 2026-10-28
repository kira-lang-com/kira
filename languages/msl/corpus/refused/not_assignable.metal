#include <metal_stdlib>
using namespace metal;
kernel void k(constant float& c [[buffer(0)]]) {
    c = 2.0;
}
