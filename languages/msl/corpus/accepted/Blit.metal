#include <metal_stdlib>
using namespace metal;

kernel void blit(texture2d<float, access::read> source [[texture(0)]],
                 texture2d<float, access::write> target [[texture(1)]],
                 texture2d<uint, access::read_write> counts [[texture(2)]],
                 uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= target.get_width() || gid.y >= target.get_height()) {
        return;
    }
    float4 texel = source.read(gid);
    float2x2 rotation = float2x2(float2(0, 1), float2(-1, 0));
    float2 turned = rotation * texel.xy;
    uint bits = as_type<uint>(turned.x);
    int signedBits = as_type<int>(bits) >> 2;
    texel.xy = select(turned, texel.yx, bool2(signedBits < 0, false));
    target.write(texel, gid);
    uint4 count = counts.read(gid);
    counts.write(count + 1u, gid);
    float total = 0;
    int index = 0;
    while (true) {
        if (index >= 4) { break; }
        total += texel[index];
        index += 1;
    }
    float values[3] = {1.0, 2.0, 3.0};
    total = total * values[gid.x % 3] + rint(total) + round(total) + fmod(total, 2.0);
    target.write(float4(total), gid / 2);
}
