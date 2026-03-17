#pragma once

// Bindgen shim: make sokol_glue.h see the dependent sokol types.
// This header is used only for binding generation.

#define SOKOL_NO_DEPRECATED
#define SOKOL_METAL

#include "sokol_app.h"
#include "sokol_gfx.h"
#include "sokol_glue.h"

