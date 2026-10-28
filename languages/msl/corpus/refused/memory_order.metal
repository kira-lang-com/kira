#include <metal_stdlib>
using namespace metal;
kernel void k(device atomic_uint* c [[buffer(0)]]) {
    atomic_fetch_add_explicit(&c[0], 1u, memory_order_seq_cst);
}
