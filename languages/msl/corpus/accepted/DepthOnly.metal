#include <metal_stdlib>
using namespace metal;

struct Camera {
    float4x4 viewProjection;
};

struct VertexIn {
    float3 position [[attribute(0)]];
};

vertex float4 depth_vertex(VertexIn in [[stage_in]], constant Camera& camera [[buffer(0)]]) {
    return camera.viewProjection * float4(in.position, 1.0);
}
