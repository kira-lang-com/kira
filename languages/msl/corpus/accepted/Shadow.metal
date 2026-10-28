#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float3 position [[attribute(0)]];
    float2 uv [[attribute(1)]];
};

struct Varyings {
    float4 position [[position]];
    float2 uv;
    float4 shadowCoord [[user(shadow)]];
    float depth [[user(depth), center_no_perspective]];
};

struct Camera {
    float4x4 viewProjection;
    float4x4 lightViewProjection;
    float3 tint;
};

vertex Varyings shadowVertex(VertexIn in [[stage_in]], constant Camera& camera [[buffer(1)]],
                             uint instance [[instance_id]]) {
    Varyings out;
    float4 world = float4(in.position + float3(float(instance), 0, 0), 1.0);
    out.position = camera.viewProjection * world;
    out.uv = in.uv;
    out.shadowCoord = camera.lightViewProjection * world;
    out.depth = out.position.z / out.position.w;
    return out;
}

float shadowFactor(depth2d<float> map, sampler compare, float4 coord) {
    float3 projected = coord.xyz / coord.w;
    float2 uv = projected.xy * float2(0.5, -0.5) + 0.5;
    return map.sample_compare(compare, uv, projected.z, level(0));
}

struct Output {
    float4 color [[color(0)]];
    float depth [[depth(any)]];
};

fragment Output shadowFragment(Varyings in [[stage_in]],
                               constant Camera& camera [[buffer(1)]],
                               texture2d<float> albedo [[texture(0)]],
                               depth2d<float> shadowMap [[texture(1)]],
                               sampler linear [[sampler(0)]],
                               sampler compare [[sampler(1)]],
                               bool front [[front_facing]]) {
    float4 base = albedo.sample(linear, in.uv);
    float lit = shadowFactor(shadowMap, compare, in.shadowCoord);
    float3 color = base.rgb * camera.tint * mix(0.3, 1.0, lit);
    color.gb = front ? color.gb : color.bg;
    float3 pixel = dfdx(color) + fwidth(color);
    Output out;
    out.color = float4(saturate(color + pixel * 0.0), base.a);
    out.depth = in.depth;
    if (base.a < 0.01) {
        discard_fragment();
    }
    return out;
}
