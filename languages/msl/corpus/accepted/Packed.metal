#include <metal_stdlib>
using namespace metal;

struct Particle {
    packed_float3 position;
    float mass;
    packed_float3 velocity;
};

kernel void integrate(device Particle* particles [[buffer(0)]], constant float& dt [[buffer(1)]],
                      uint id [[thread_position_in_grid]]) {
    Particle p = particles[id];
    float3 velocity = p.velocity;
    velocity.y -= 9.8f * dt / max(p.mass, 0.001f);
    particles[id].velocity = velocity;
    particles[id].position = float3(p.position) + velocity * dt;
}
