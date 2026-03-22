#define SOKOL_NO_ENTRY
#define SOKOL_DLL
#define SOKOL_APP_IMPL
#define SOKOL_GFX_IMPL
#define SOKOL_GLUE_IMPL
#define SOKOL_D3D11
#define SOKOL_WIN32
#define SOKOL_NO_DEPRECATED

#include <stdint.h>
#include "sokol_app.h"
#include "sokol_gfx.h"
#include "sokol_glue.h"

__declspec(dllexport) int64_t kira_is_d3d11(void) {
    return (sg_query_backend() == SG_BACKEND_D3D11) ? 1 : 0;
}

__declspec(dllexport) void kira_sg_setup(void) {
    sg_desc desc = {0};
    desc.environment = sglue_environment();
    sg_setup(&desc);
}

__declspec(dllexport) void kira_sapp_run(void* init_cb, void* frame_cb, void* cleanup_cb, int32_t width, int32_t height, const char* window_title) {
    sapp_desc desc = {0};
    desc.init_cb = init_cb;
    desc.frame_cb = frame_cb;
    desc.cleanup_cb = cleanup_cb;
    desc.width = width;
    desc.height = height;
    desc.window_title = window_title;
    sapp_run(&desc);
}
