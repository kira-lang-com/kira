#include <metal_stdlib>
using namespace metal;
struct Out { float4 position [[position]]; half4 tint [[user(tint)]]; };
vertex Out vs(uint id [[vertex_id]]) {
    Out o;
    float2 p = float2(float(id & 1u), float(id >> 1));
    o.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
    o.tint = half4(half(0.5), 1.0h, 0.25h, 1.0h);
    return o;
}
fragment half4 fs(Out in [[stage_in]]) {
    half3 c = in.tint.rgb * 2.0h;
    return half4(clamp(c, half3(0.0h), half3(1.0h)), in.tint.a);
}
