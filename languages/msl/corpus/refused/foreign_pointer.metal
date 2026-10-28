#include <metal_stdlib>
using namespace metal;
struct Item { float value; };
float first(device Item& item) { return item.value; }
kernel void k(device Item* items [[buffer(0)]]) {
    float x = first(items[1]);
}
