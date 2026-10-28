#include <metal_stdlib>
using namespace metal;
struct A { float x; };
struct B { float y; };
float f(A a) { return a.x; }
float f(float3 v) { return v.x; }
kernel void k() {
    B b = {};
    float x = f(b);
}
