#include <metal_stdlib>
using namespace metal;
vertex float4 v(constant float4& a [[buffer(0)]]) { return a; }
fragment float4 f(constant float2& b [[buffer(0)]]) { return float4(b, 0, 1); }
