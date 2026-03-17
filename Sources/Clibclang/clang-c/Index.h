#pragma once
// SwiftPM system-library shim header.
// The module.modulemap references "clang-c/Index.h" relative to this directory, but
// the real libclang C API header lives in the system/brew include path.
#include_next <clang-c/Index.h>
