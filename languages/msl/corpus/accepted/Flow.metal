// Loops with `break` and `continue`, `do`/`while`, and a `switch` whose
// cases fall through and break early: the shapes the KSL out writes with
// flags.

#include <metal_stdlib>
using namespace metal;

float weigh(int kind, float value) {
    float result = 0.0;
    switch (kind) {
        case 0:
        case 1:
            result = value;
            break;
        case 2:
            if (value < 0.0) {
                result = -value;
                break;
            }
            result = value * 2.0;
            break;
        default:
            result = 1.0;
            break;
    }
    return result;
}

kernel void flow(device float* values [[buffer(0)]],
                 uint index [[thread_position_in_grid]]) {
    float total = 0.0;
    for (int i = 0; i < 16; i++) {
        if (i == 3) {
            continue;
        }
        total += weigh(i % 4, float(i));
        if (total > 100.0) {
            break;
        }
    }
    int j = 0;
    do {
        total += 0.5;
        j++;
    } while (j < 4);
    values[index] = total;
}
