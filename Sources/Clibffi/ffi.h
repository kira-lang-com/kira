#pragma once
// SwiftPM system-library shim header.
// The module.modulemap references "ffi.h" relative to this directory, but the real
// libffi header lives in the system/brew include path. `include_next` forwards to it.
#include_next <ffi.h>
