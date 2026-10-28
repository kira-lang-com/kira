#include <metal_stdlib>
using namespace metal;
kernel void k(device float* data [[buffer(0)]]) {
    float x = *(data + 1);
}
