#include <metal_stdlib>
using namespace metal;

#define GROUP 64

constant uint scale [[function_constant(0)]];
constant float bias = 0.5f;
constant float shifted = bias * 2.0f;

struct Params {
    uint count;
    float3 offset;
    float weight;
};

namespace math {
    template <typename T>
    T square(T value) { return value * value; }

    inline float weighted(float value, constant Params& params) {
        return value * params.weight + params.offset.x;
    }
}

uint bucketOf(uint value) {
    switch (value % 4u) {
        case 0:
        case 1:
            return 0u;
        case 2:
            return 1u;
        default:
            break;
    }
    return 2u;
}

void accumulate(device atomic_uint* counters, uint bucket, uint amount) {
    atomic_fetch_add_explicit(&counters[bucket], amount, memory_order_relaxed);
}

kernel void reduce(const device float* input [[buffer(0)]],
                   device float* output [[buffer(1)]],
                   device atomic_uint* counters [[buffer(2)]],
                   constant Params& params [[buffer(3)]],
                   uint gid [[thread_position_in_grid]],
                   uint lid [[thread_index_in_threadgroup]],
                   uint2 group [[threadgroup_position_in_grid]],
                   uint3 size [[threads_per_threadgroup]]) {
    threadgroup float shared[GROUP];
    float value = gid < params.count ? input[gid] : 0.0f;
    shared[lid] = math::square(math::weighted(value, params)) + shifted;
    threadgroup_barrier(mem_flags::mem_threadgroup);
    for (uint stride = size.x / 2; stride > 0; stride >>= 1) {
        if (lid < stride) {
            shared[lid] += shared[lid + stride];
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }
    if (lid == 0) {
        output[group.x] = shared[0] * float(scale);
        accumulate(counters, bucketOf(group.x), 1u);
    }
    int steps = 0;
    do {
        steps++;
    } while (steps < 3 && lid == 0);
    uint old = atomic_load_explicit(&counters[3], memory_order_relaxed);
    if (old > 100u && math::square(int(old)) > 0) {
        atomic_store_explicit(&counters[3], 0u, memory_order_relaxed);
    }
}
