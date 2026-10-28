#include <metal_stdlib>
using namespace metal;
struct In { float4 color [[color(0)]]; };
vertex float4 v(In in [[stage_in]]) { return in.color; }
fragment float4 f() { return float4(1); }
