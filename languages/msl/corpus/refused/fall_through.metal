#include <metal_stdlib>
using namespace metal;
kernel void k(uint id [[thread_position_in_grid]]) {
    switch (id) {
    case 0:
        id += 1;
    case 1:
        break;
    }
}
