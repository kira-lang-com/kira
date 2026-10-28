#include <metal_stdlib>
using namespace metal;
struct Pixel { float4 color [[raster_order_group(0)]]; };
kernel void k() {}
